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

        if (pickupLat == null || pickupLng == null
                || deliveryLat == null || deliveryLng == null) {
            return deliveryMinFee.setScale(2, RoundingMode.HALF_UP);
        }

        double distanceKm = haversineKm(
                pickupLat, pickupLng, deliveryLat, deliveryLng);

        BigDecimal fee = deliveryBaseFee.add(
                deliveryRatePerKm.multiply(
                        BigDecimal.valueOf(distanceKm)));

        if (fee.compareTo(deliveryMinFee) < 0) {
            fee = deliveryMinFee;
        }

        return fee.setScale(2, RoundingMode.HALF_UP);
    }

    // ─────────────────────────────────────────────────
    // RIDE FEE (MOBILITY) — same distance-based approach,
    // separate configurable rate from delivery.
    // ─────────────────────────────────────────────────
    public BigDecimal calculateRideFee(
            Double pickupLat, Double pickupLng,
            Double deliveryLat, Double deliveryLng) {

        if (pickupLat == null || pickupLng == null
                || deliveryLat == null || deliveryLng == null) {
            return rideMinFee.setScale(2, RoundingMode.HALF_UP);
        }

        double distanceKm = haversineKm(
                pickupLat, pickupLng, deliveryLat, deliveryLng);

        BigDecimal fee = rideBaseFee.add(
                rideRatePerKm.multiply(
                        BigDecimal.valueOf(distanceKm)));

        if (fee.compareTo(rideMinFee) < 0) {
            fee = rideMinFee;
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