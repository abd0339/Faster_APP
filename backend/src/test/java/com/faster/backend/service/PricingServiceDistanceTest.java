package com.faster.backend.service;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.reflect.Method;
import java.math.BigDecimal;
import java.time.Duration;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import com.faster.backend.exception.BusinessException;
import com.faster.backend.repository.ItemAddonRepository;
import com.faster.backend.repository.ItemRepository;
import com.faster.backend.repository.ModifierOptionRepository;

/**
 * Covers PricingService.exceedsMaxDeliveryDistance (input-hardening plan,
 * Task 3) — the distance-cap check later wired into OrderService's
 * order-creation and location-update call sites (Tasks 5 and 6).
 */
@ExtendWith(MockitoExtension.class)
class PricingServiceDistanceTest {

    @Mock
    private ItemRepository itemRepository;

    @Mock
    private ModifierOptionRepository modifierOptionRepository;

    @Mock
    private ItemAddonRepository addonRepository;

    private PricingService pricingService;

    @BeforeEach
    void setUp() {
        pricingService = new PricingService(
                itemRepository, modifierOptionRepository, addonRepository);
        // @Value fields are only populated by Spring; this is a plain unit
        // test, so set the field directly to match the configured default
        // (application.properties: delivery.max-distance-km=6.0).
        ReflectionTestUtils.setField(
                pricingService, "maxDeliveryDistanceKm", 6.0);
        // Same for the O2O price-guardrail @Value fields — defaults
        // match PricingService's own @Value defaults.
        ReflectionTestUtils.setField(
                pricingService, "o2oMinPrice", new BigDecimal("1.00"));
        ReflectionTestUtils.setField(
                pricingService, "o2oMaxPrice", new BigDecimal("1000.00"));
        ReflectionTestUtils.setField(
                pricingService, "o2oReviewThreshold", new BigDecimal("5.00"));
        // validateDirectDeliveryItemValue's @Value field.
        ReflectionTestUtils.setField(
                pricingService, "directDeliveryMaxItemValue", new BigDecimal("50000.00"));
    }

    @Test
    void exceedsMaxDeliveryDistance_falseWhenAnyCoordNull() {
        assertFalse(pricingService.exceedsMaxDeliveryDistance(
                null, null, 33.8, 35.5));
    }

    @Test
    void exceedsMaxDeliveryDistance_falseWellWithinCap() {
        // Beirut downtown -> Hamra, roughly ~1km apart
        double pickupLat = 33.8938;
        double pickupLng = 35.5018;
        double deliveryLat = 33.9038;
        double deliveryLng = 35.5018;

        assertFalse(pricingService.exceedsMaxDeliveryDistance(
                pickupLat, pickupLng, deliveryLat, deliveryLng));
    }

    @Test
    void exceedsMaxDeliveryDistance_trueWellBeyondCap() {
        // Beirut vs. North Lebanon (Akkar area), ~90km+ apart
        double pickupLat = 33.8938;
        double pickupLng = 35.5018;
        double deliveryLat = 34.55;
        double deliveryLng = 36.10;

        assertTrue(pricingService.exceedsMaxDeliveryDistance(
                pickupLat, pickupLng, deliveryLat, deliveryLng));
    }

    @Test
    void exceedsMaxDeliveryDistance_boundaryExactlyAtCap() throws Exception {
        double pickupLat = 33.8938;
        double pickupLng = 35.5018;
        double deliveryLat = 33.9480;
        double deliveryLng = 35.5018;

        // Compute the exact haversine distance for these two points (using
        // the production private method itself, so this is bit-for-bit the
        // same value exceedsMaxDeliveryDistance will compute internally),
        // then set the cap to that exact value. This proves the comparison
        // is strictly-greater-than: a distance exactly equal to the cap
        // must NOT be treated as exceeding it.
        Method haversineKm = PricingService.class.getDeclaredMethod(
                "haversineKm",
                double.class, double.class, double.class, double.class);
        haversineKm.setAccessible(true);
        double exactDistanceKm = (double) haversineKm.invoke(
                pricingService, pickupLat, pickupLng, deliveryLat, deliveryLng);

        ReflectionTestUtils.setField(
                pricingService, "maxDeliveryDistanceKm", exactDistanceKm);

        assertFalse(pricingService.exceedsMaxDeliveryDistance(
                pickupLat, pickupLng, deliveryLat, deliveryLng));
    }

    // ───────────────────────────────────────────────────────────
    // A coordinate that overflows a double
    // to +/-Infinity (e.g. a client sending "1e400" for a lat/lng,
    // which Jackson happily parses into a finite-looking Double
    // field as Double.POSITIVE_INFINITY) feeds into the haversine
    // formula and produces distanceKm == NaN (Math.sin/cos of an
    // infinite radian value is NaN by spec). Before this fix,
    // `distanceKm > maxDeliveryDistanceKm` is FALSE for NaN (NaN
    // compares false to everything), so the method silently
    // reported "not exceeding" — a genuine bypass of the hard
    // distance cap via malformed-but-type-valid input, not just a
    // display glitch. Fail-safe fix: treat a non-finite distance as
    // exceeding the cap.
    // ───────────────────────────────────────────────────────────
    @Test
    void exceedsMaxDeliveryDistance_trueWhenCoordinateIsInfinite() {
        assertTrue(pricingService.exceedsMaxDeliveryDistance(
                0.0, 0.0, Double.POSITIVE_INFINITY, 0.0));
    }

    @Test
    void exceedsMaxDeliveryDistance_trueWhenCoordinateProducesNaNDistance() {
        // lng difference of exactly +/-Infinity's radian conversion
        // reliably yields NaN through sin(); also cover the
        // "both coordinates infinite" case.
        assertTrue(pricingService.exceedsMaxDeliveryDistance(
                Double.POSITIVE_INFINITY, Double.POSITIVE_INFINITY,
                Double.NEGATIVE_INFINITY, Double.NEGATIVE_INFINITY));
    }

    @Test
    void exceedsMaxDeliveryDistance_handlesOriginCoordinateWithoutCrashing() {
        // (0,0) is a legitimate (if unusual) coordinate — must not
        // be treated as "missing" (that's null, handled separately)
        // and must not crash.
        assertFalse(pricingService.exceedsMaxDeliveryDistance(
                0.0, 0.0, 0.001, 0.001));
    }

    @Test
    void exceedsMaxDeliveryDistance_handlesSwappedLatLngWithoutCrashing() {
        // Caller accidentally swapped lat/lng (sends lng where lat
        // is expected and vice versa) — still just two finite
        // numbers to the formula; must resolve to a boolean, never
        // throw.
        double swappedPickupLat = 35.5018; // actually a longitude
        double swappedPickupLng = 33.8938; // actually a latitude
        double swappedDeliveryLat = 35.8497;
        double swappedDeliveryLng = 34.4367;

        assertDoesNotThrow(() -> pricingService.exceedsMaxDeliveryDistance(
                swappedPickupLat, swappedPickupLng,
                swappedDeliveryLat, swappedDeliveryLng));
    }

    // ───────────────────────────────────────────────────────────
    // calculateDeliveryFee / calculateRideFee share the same
    // haversine-based distanceKm computation (calculateDistanceFee).
    // Before this fix, a non-finite distanceKm reached
    // `BigDecimal.valueOf(distanceKm)`, which throws a raw, leaky
    // NumberFormatException ("For input string: \"NaN\"") instead
    // of a clean, intentional 4xx message. Fixed the same way: fail
    // fast with a BusinessException as soon as the distance itself
    // is detected as non-finite, before any BigDecimal math runs.
    // ───────────────────────────────────────────────────────────
    @Test
    void calculateDeliveryFee_throwsBusinessException_whenDistanceIsNonFinite() {
        assertThrows(BusinessException.class, () -> pricingService.calculateDeliveryFee(
                0.0, 0.0, Double.POSITIVE_INFINITY, 0.0));
    }

    @Test
    void calculateRideFee_throwsBusinessException_whenDistanceIsNonFinite() {
        assertThrows(BusinessException.class, () -> pricingService.calculateRideFee(
                0.0, 0.0, Double.POSITIVE_INFINITY, 0.0));
    }

    // ───────────────────────────────────────────────────────────
    // validateO2OPrice — BigDecimal values with pathological scale
    // or precision must still be bounded/rejected cleanly rather
    // than crashing. BigDecimal.compareTo() is scale-independent
    // (it compares numeric VALUE, not representation), so this is
    // expected to already hold — this test proves it, it doesn't
    // fix anything.
    // ───────────────────────────────────────────────────────────
    @Test
    void validateO2OPrice_rejectsExcessivePrecisionAboveMax() {
        // A 30-digit integer, nowhere near the $1000 max.
        BigDecimal hugePrecision = new BigDecimal("123456789012345678901234567890");
        assertThrows(BusinessException.class,
                () -> pricingService.validateO2OPrice(hugePrecision));
    }

    @Test
    void validateO2OPrice_rejectsExcessiveScaleBelowMin() {
        // 50 decimal places, numerically far below the $1 minimum.
        BigDecimal tinyScale = new BigDecimal(
                "0.00000000000000000000000000000000000000000000001");
        assertThrows(BusinessException.class,
                () -> pricingService.validateO2OPrice(tinyScale));
    }

    @Test
    void validateO2OPrice_handlesExcessiveScaleWithinReviewRangeWithoutCrashing() {
        // 40 decimal places but numerically within the no-review
        // range ($5-$1000) once you look past all the trailing
        // zeros/digits — must not crash, and must not flag.
        BigDecimal preciseButValid = new BigDecimal(
                "10.0000000000000000000000000000000000000001");
        String reason = assertDoesNotThrow(
                () -> pricingService.validateO2OPrice(preciseButValid));
        assertTrue(reason == null);
    }

    // ───────────────────────────────────────────────────────────
    // validateDirectDeliveryItemValue: Direct Delivery's declared
    // item value had no upper bound, while Order.totalPrice/
    // grandTotal are NUMERIC(10,2) columns (max 99,999,999.99).
    // ───────────────────────────────────────────────────────────
    @Test
    void validateDirectDeliveryItemValue_acceptsTypicalValue() {
        assertDoesNotThrow(() -> pricingService.validateDirectDeliveryItemValue(
                new BigDecimal("25.00")));
    }

    @Test
    void validateDirectDeliveryItemValue_acceptsZero() {
        // Unlike O2O, there's no minimum — a customer's own package can
        // legitimately be declared as worth very little.
        assertDoesNotThrow(() -> pricingService.validateDirectDeliveryItemValue(
                BigDecimal.ZERO));
    }

    @Test
    void validateDirectDeliveryItemValue_acceptsExactlyAtMax() {
        assertDoesNotThrow(() -> pricingService.validateDirectDeliveryItemValue(
                new BigDecimal("50000.00")));
    }

    @Test
    void validateDirectDeliveryItemValue_rejectsJustAboveMax() {
        assertThrows(BusinessException.class,
                () -> pricingService.validateDirectDeliveryItemValue(
                        new BigDecimal("50000.01")));
    }

    @Test
    void validateDirectDeliveryItemValue_rejectsAbsurdlyHugeValue() {
        assertThrows(BusinessException.class,
                () -> pricingService.validateDirectDeliveryItemValue(
                        new BigDecimal("1E10")));
    }

    // ───────────────────────────────────────────────────────────
    // rejectIfScaleIsDangerous (closes a BigDecimal scale/exponent
    // DoS): a huge-exponent value like
    // "1e10000000" is only an 11-character JSON token (not caught by
    // Jackson's own max-number-LENGTH guard), but
    // BigDecimal.setScale(2, ...) on it was measured at ~8.8 SECONDS
    // in this exact codebase. These tests prove the ordering, not
    // just eventual rejection: assertTimeoutPreemptively fails the
    // test outright if the call takes anywhere near that long, so a
    // regression back to "check after setScale" would make these
    // tests fail on the timeout, not just on a wrong result.
    // ───────────────────────────────────────────────────────────
    @Test
    void rejectIfScaleIsDangerous_rejectsHugePositiveExponent_withinOneSecond() {
        BigDecimal huge = new BigDecimal("1e10000000");
        assertTimeoutPreemptively(Duration.ofSeconds(1), () ->
                assertThrows(BusinessException.class,
                        () -> pricingService.rejectIfScaleIsDangerous(huge)));
    }

    @Test
    void rejectIfScaleIsDangerous_rejectsHugeNegativeExponent_withinOneSecond() {
        BigDecimal tiny = new BigDecimal("1e-10000000");
        assertTimeoutPreemptively(Duration.ofSeconds(1), () ->
                assertThrows(BusinessException.class,
                        () -> pricingService.rejectIfScaleIsDangerous(tiny)));
    }

    @Test
    void rejectIfScaleIsDangerous_acceptsNormalScale() {
        assertDoesNotThrow(() -> pricingService.rejectIfScaleIsDangerous(
                new BigDecimal("50000.00")));
    }

    @Test
    void rejectIfScaleIsDangerous_acceptsNull() {
        assertDoesNotThrow(() -> pricingService.rejectIfScaleIsDangerous(null));
    }

    @Test
    void rejectIfScaleIsDangerous_acceptsScaleExactlyAtBoundary() {
        BigDecimal atBoundary = BigDecimal.ONE.setScale(100);
        assertDoesNotThrow(() -> pricingService.rejectIfScaleIsDangerous(atBoundary));
    }

    @Test
    void rejectIfScaleIsDangerous_rejectsScaleJustOverBoundary() {
        BigDecimal overBoundary = new BigDecimal("1e-101"); // scale = 101
        assertThrows(BusinessException.class,
                () -> pricingService.rejectIfScaleIsDangerous(overBoundary));
    }
}
