package com.faster.backend.service;

import com.faster.backend.dto.OrderItemLineRequest;
import com.faster.backend.entity.Item;
import com.faster.backend.entity.ItemAddon;
import com.faster.backend.entity.ModifierOption;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.repository.ItemAddonRepository;
import com.faster.backend.repository.ItemRepository;
import com.faster.backend.repository.ModifierOptionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;

/**
 * CLOSES AUDIT ITEM C2 (Critical) — Server-side pricing.
 *
 * Previously: totalPrice and deliveryFee/rideFee came straight from the
 * client (Flutter app) and were trusted as-is. A customer could POST
 * {"totalPrice": 0.01} and the platform's 10%/20% commission would be
 * calculated on a fake number.
 *
 * Now: this service is the ONLY place that computes money. It re-derives
 * item totals from the merchant's own catalog (never the client's number)
 * and derives delivery/ride fees from real pickup→delivery distance.
 * Any client-sent price fields are ignored entirely — see OrderRequest.
 */
@Service
@RequiredArgsConstructor
public class PricingService {

    // ─── BigDecimal scale/exponent DoS guard ──────────
    // BigDecimal.setScale (and most BigDecimal arithmetic that must
    // realign the decimal point) on a value with an extreme scale is
    // computationally dangerous: internally it has to construct a
    // BigInteger with roughly |scale| digits. A client sending
    // {"totalPrice": 1e10000000} — an 11-character JSON token, NOT
    // caught by Jackson's own default max-number-LENGTH guard, since
    // the token itself is short even though the resulting scale is
    // enormous — measured at ~8.8 SECONDS for a single setScale(2,...)
    // call in this exact codebase. BigDecimal.scale() is a plain
    // stored field: reading it is always O(1) regardless of
    // magnitude, so checking it BEFORE any setScale/arithmetic call
    // is the correct, cheap place to reject a dangerous value.
    //
    // NOTE: compareTo() against a small-magnitude reference constant
    // (e.g. BigDecimal.ZERO, or the o2o/direct-delivery bound checks
    // below) is SEPARATELY safe even for a huge-scale value — verified
    // empirically (0ms for the same "1e10000000" against a small
    // constant) — because BigDecimal.compareTo short-circuits via an
    // internal "adjusted exponent" estimate when the two values'
    // magnitudes are clearly different, without ever needing to
    // align scales. So this guard is specifically required before
    // setScale, not before a compareTo-based bounds check.
    private static final int MAX_ABS_SCALE = 100;

    public void rejectIfScaleIsDangerous(BigDecimal value) {
        if (value != null && Math.abs(value.scale()) > MAX_ABS_SCALE) {
            throw new BusinessException(
                    "Amount has an invalid number of digits");
        }
    }

    private final ItemRepository itemRepository;
    private final ModifierOptionRepository modifierOptionRepository;
    private final ItemAddonRepository addonRepository;

    // ─── Delivery fee (LOGISTICS) — distance-based ───
    @Value("${pricing.delivery.base-fee:1.00}")
    private BigDecimal deliveryBaseFee;

    @Value("${pricing.delivery.rate-per-km:0.50}")
    private BigDecimal deliveryRatePerKm;

    @Value("${pricing.delivery.min-fee:1.50}")
    private BigDecimal deliveryMinFee;

    // ─── O2O manual price guardrails (M3 fix) ────────
    // O2O keeps manual price entry (phone orders can include
    // off-catalog items — see Order.isPriceFlagged), but these
    // bound it: hard-reject obvious typos/fraud, soft-flag
    // anything merely low for admin review.
    @Value("${pricing.o2o.min-price:1.00}")
    private BigDecimal o2oMinPrice;

    @Value("${pricing.o2o.max-price:1000.00}")
    private BigDecimal o2oMaxPrice;

    @Value("${pricing.o2o.review-threshold:5.00}")
    private BigDecimal o2oReviewThreshold;

    // ─── Direct Delivery item-value guardrail ─────────
    // itemValue is the customer's OWN declared package value (see
    // OrderService.createDirectDeliveryOrder) — legitimately
    // customer-set, unlike O2O's merchant-set totalPrice, so the
    // $1000 O2O ceiling doesn't apply here. But it was completely
    // unbounded server-side: Order.totalPrice/grandTotal are both
    // NUMERIC(10,2) columns (max 99,999,999.99), and a value near or
    // above that throws a raw DataIntegrityViolationException once
    // persisted — caught only generically by GlobalExceptionHandler,
    // leaking SQL/constraint text to the client. Bounded well under
    // the column's real max so grandTotal (itemValue + deliveryFee)
    // can never overflow either.
    @Value("${pricing.direct-delivery.max-item-value:50000.00}")
    private BigDecimal directDeliveryMaxItemValue;

    // ─── Max delivery distance (input-hardening) ─────
    // Hard cap on pickup→delivery straight-line distance; orders/location
    // updates beyond this are rejected by OrderService (Tasks 5 and 6),
    // not by this service — this method only answers the yes/no question.
    @Value("${delivery.max-distance-km:6.0}")
    private double maxDeliveryDistanceKm;

    // ─── Ride fee (MOBILITY) — distance-based ────────
    @Value("${pricing.ride.base-fee:1.50}")
    private BigDecimal rideBaseFee;

    @Value("${pricing.ride.rate-per-km:0.60}")
    private BigDecimal rideRatePerKm;

    @Value("${pricing.ride.min-fee:2.00}")
    private BigDecimal rideMinFee;

    // Earth radius in km, for haversine
    private static final double EARTH_RADIUS_KM = 6371.0;

    // ─────────────────────────────────────────────────
    // ITEM PRICING — the C2 fix
    // Recomputes the order total from the merchant's own
    // catalog. Client-sent prices are never trusted.
    // ─────────────────────────────────────────────────
    public BigDecimal calculateItemsTotal(
            Long merchantId,
            List<OrderItemLineRequest> lines) {

        if (lines == null || lines.isEmpty()) {
            throw new BusinessException(
                    "Order must contain at least one item");
        }

        BigDecimal total = BigDecimal.ZERO;

        for (OrderItemLineRequest line : lines) {

            if (line.getQuantity() == null || line.getQuantity() < 1) {
                throw new BusinessException(
                        "Quantity must be at least 1 for item "
                        + line.getItemId());
            }

            // Look up the item AND verify it belongs to this merchant.
            // Prevents cross-store price mixing / spoofed item IDs.
            Item item = itemRepository
                    .findByIdAndMerchantId(line.getItemId(), merchantId)
                    .orElseThrow(() -> new BusinessException(
                            "Item " + line.getItemId()
                            + " was not found in this store"));

            if (Boolean.FALSE.equals(item.getIsAvailable())
                    || Boolean.TRUE.equals(item.getIsSnoozed())) {
                throw new BusinessException(
                        "\"" + item.getName()
                        + "\" is currently unavailable");
            }

            if (item.getStockQuantity() != null
                    && item.getStockQuantity() != -1
                    && item.getStockQuantity() < line.getQuantity()) {
                throw new BusinessException(
                        "\"" + item.getName()
                        + "\" does not have enough stock");
            }

            // Base item price (server-side, never client-side)
            BigDecimal lineUnitPrice = item.getPrice();

            // Add selected modifier options (e.g. "Large +$1.00")
            // — each verified to belong to THIS merchant
            if (line.getModifierOptionIds() != null) {
                for (Long optionId : line.getModifierOptionIds()) {
                    ModifierOption option = modifierOptionRepository
                            .findByIdAndMerchantId(optionId, merchantId)
                            .orElseThrow(() -> new BusinessException(
                                    "Invalid modifier option " + optionId));
                    lineUnitPrice = lineUnitPrice.add(
                            option.getExtraPrice() != null
                                    ? option.getExtraPrice()
                                    : BigDecimal.ZERO);
                }
            }

            // Add selected addons (e.g. "Extra Cheese +$0.50")
            if (line.getAddonIds() != null) {
                for (Long addonId : line.getAddonIds()) {
                    ItemAddon addon = addonRepository
                            .findByIdAndMerchantId(addonId, merchantId)
                            .orElseThrow(() -> new BusinessException(
                                    "Invalid addon " + addonId));
                    lineUnitPrice = lineUnitPrice.add(
                            addon.getExtraPrice() != null
                                    ? addon.getExtraPrice()
                                    : BigDecimal.ZERO);
                }
            }

            // Item-level service fee, if the merchant set one
            if (item.getServiceFee() != null
                    && item.getServiceFee().compareTo(BigDecimal.ZERO) > 0) {
                lineUnitPrice = lineUnitPrice.add(item.getServiceFee());
            }

            BigDecimal lineTotal = lineUnitPrice
                    .multiply(BigDecimal.valueOf(line.getQuantity()));

            total = total.add(lineTotal);
        }

        return total.setScale(2, RoundingMode.HALF_UP);
    }

    // ─────────────────────────────────────────────────
    // Decrement stock for each ordered line.
    // Call ONLY after calculateItemsTotal() has validated
    // availability, and only once per successfully created order.
    // Skips items with unlimited stock (-1).
    // ─────────────────────────────────────────────────
    public void decrementStockForOrder(List<OrderItemLineRequest> lines) {
        if (lines == null) return;
        for (OrderItemLineRequest line : lines) {
            Item item = itemRepository.findById(line.getItemId())
                    .orElse(null);
            if (item == null) continue;
            if (item.getStockQuantity() != null
                    && item.getStockQuantity() != -1) {
                itemRepository.decrementStock(
                        line.getItemId(), line.getQuantity());
            }
        }
    }

    // ─────────────────────────────────────────────────
    // O2O MANUAL PRICE CHECK (M3 fix)
    // Hard-rejects values that can only be a typo or an
    // attempt to dodge commission (e.g. $0.01). Returns a
    // non-null reason string when the price is merely LOW
    // enough to deserve a human look, without blocking the
    // order — callers should flag it (Order.isPriceFlagged)
    // rather than reject it. Returns null when the price
    // needs no review.
    // ─────────────────────────────────────────────────
    public String validateO2OPrice(BigDecimal totalPrice) {

        if (totalPrice.compareTo(o2oMinPrice) < 0) {
            throw new BusinessException(
                    "Order price must be at least $" + o2oMinPrice);
        }

        if (totalPrice.compareTo(o2oMaxPrice) > 0) {
            throw new BusinessException(
                    "Order price of $" + totalPrice
                    + " looks like a mistake (over $" + o2oMaxPrice
                    + "). Double-check the amount.");
        }

        if (totalPrice.compareTo(o2oReviewThreshold) < 0) {
            return "O2O price $" + totalPrice
                    + " is below the $" + o2oReviewThreshold
                    + " review threshold";
        }

        return null;
    }

    // ─────────────────────────────────────────────────
    // DIRECT DELIVERY ITEM-VALUE CHECK
    // Hard-rejects a declared package value that's absurdly large —
    // not a typo-guard like O2O's $1 minimum (a customer's own
    // package can legitimately be worth very little), just an upper
    // bound well under what Order.totalPrice/grandTotal's
    // NUMERIC(10,2) columns can actually hold, so a huge value never
    // reaches persistence and overflows them.
    // ─────────────────────────────────────────────────
    public void validateDirectDeliveryItemValue(BigDecimal itemValue) {
        if (itemValue.compareTo(directDeliveryMaxItemValue) > 0) {
            throw new BusinessException(
                    "Declared item value of $" + itemValue
                    + " looks like a mistake (max $"
                    + directDeliveryMaxItemValue
                    + "). Double-check the amount.");
        }
    }

    // ─────────────────────────────────────────────────
    // DELIVERY FEE (LOGISTICS) — distance-based
    // base fee + (rate per km × distance), floored at min fee.
    //
    // Falls back to the minimum fee if coordinates are missing
    // (e.g. O2O "phone bridge" flow where the offline customer
    // hasn't shared their location yet at order-creation time —
    // the fee should be finalized once the tracking link captures
    // real coordinates; this is a known, intentional fallback,
    // not a silent gap).
    // ─────────────────────────────────────────────────
    public BigDecimal calculateDeliveryFee(
            Double pickupLat, Double pickupLng,
            Double deliveryLat, Double deliveryLng) {
        return calculateDistanceFee(
                pickupLat, pickupLng, deliveryLat, deliveryLng,
                deliveryBaseFee, deliveryRatePerKm, deliveryMinFee);
    }

    // ─────────────────────────────────────────────────
    // RIDE FEE (MOBILITY) — same distance-based approach,
    // separate configurable rate from delivery.
    // ─────────────────────────────────────────────────
    public BigDecimal calculateRideFee(
            Double pickupLat, Double pickupLng,
            Double deliveryLat, Double deliveryLng) {
        return calculateDistanceFee(
                pickupLat, pickupLng, deliveryLat, deliveryLng,
                rideBaseFee, rideRatePerKm, rideMinFee);
    }

    // ─────────────────────────────────────────────────
    // MAX DELIVERY DISTANCE CHECK (input-hardening)
    // Answers "is this pickup→delivery pair too far apart to serve?"
    // so OrderService can reject it at order-creation and
    // location-update time (configurable cap, default 6km).
    //
    // Can't evaluate distance without all 4 coordinates — treated as
    // "not exceeding" rather than throwing, matching this class's
    // existing missing-coords philosophy (see calculateDistanceFee).
    // ─────────────────────────────────────────────────
    public boolean exceedsMaxDeliveryDistance(
            Double pickupLat, Double pickupLng,
            Double deliveryLat, Double deliveryLng) {

        if (pickupLat == null || pickupLng == null
                || deliveryLat == null || deliveryLng == null) {
            return false;
        }

        double distanceKm = haversineKm(
                pickupLat, pickupLng, deliveryLat, deliveryLng);

        // a coordinate that overflows a double
        // to +/-Infinity (e.g. a client sending "1e400" for a lat/lng —
        // syntactically a valid JSON number, which Jackson parses straight
        // into a Double field as Double.POSITIVE_INFINITY) makes the
        // haversine formula compute NaN (Math.sin/cos of an infinite
        // radian value is NaN by spec). `NaN > maxDeliveryDistanceKm` is
        // FALSE — NaN compares false to everything — so without this
        // guard the method silently reported "not exceeding the cap" for
        // exactly the malformed input the cap exists to catch. Fail safe:
        // treat an unanswerable (non-finite) distance as exceeding it.
        if (!Double.isFinite(distanceKm)) {
            return true;
        }

        return distanceKm > maxDeliveryDistanceKm;
    }

    // ─────────────────────────────────────────────────
    // Shared distance-fee calculation: calculateDeliveryFee and
    // calculateRideFee used to be two structurally identical methods
    // differing only
    // by which (baseFee, ratePerKm, minFee) triple they used — a bug
    // fix to the clamping/rounding logic had to land in both, and a
    // future fee tier would naturally have been a third copy. Base
    // fee + rate*distance, floored at minFee, rounded HALF_UP to 2dp;
    // falls back to minFee alone if either coordinate pair is missing
    // (see the class-level comment on calculateDeliveryFee above for
    // why that's an intentional fallback, not a silent gap).
    // ─────────────────────────────────────────────────
    private BigDecimal calculateDistanceFee(
            Double pickupLat, Double pickupLng,
            Double deliveryLat, Double deliveryLng,
            BigDecimal baseFee, BigDecimal ratePerKm, BigDecimal minFee) {

        if (pickupLat == null || pickupLng == null
                || deliveryLat == null || deliveryLng == null) {
            return minFee.setScale(2, RoundingMode.HALF_UP);
        }

        double distanceKm = haversineKm(
                pickupLat, pickupLng, deliveryLat, deliveryLng);

        // Same non-finite-distance case as exceedsMaxDeliveryDistance
        // above (see its comment) — without
        // this guard, BigDecimal.valueOf(NaN/Infinity) a few lines below
        // throws a raw NumberFormatException ("For input string: \"NaN\"")
        // that leaks internal detail instead of a clean, intentional
        // message. Fail fast with exactly that, before any BigDecimal
        // math runs.
        if (!Double.isFinite(distanceKm)) {
            throw new BusinessException(
                    "Invalid pickup or delivery coordinates");
        }

        BigDecimal fee = baseFee.add(
                ratePerKm.multiply(BigDecimal.valueOf(distanceKm)));

        if (fee.compareTo(minFee) < 0) {
            fee = minFee;
        }

        return fee.setScale(2, RoundingMode.HALF_UP);
    }

    // ─────────────────────────────────────────────────
    // Haversine great-circle distance in kilometers.
    // Standard formula — no external dependency needed.
    // ─────────────────────────────────────────────────
    private double haversineKm(
            double lat1, double lng1,
            double lat2, double lng2) {

        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);

        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1))
                * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);

        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

        return EARTH_RADIUS_KM * c;
    }
}