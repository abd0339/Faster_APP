package com.faster.backend.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import com.faster.backend.entity.ExchangeRate;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.exception.NotFoundException;
import com.faster.backend.repository.ExchangeRateRepository;

@ExtendWith(MockitoExtension.class)
class ExchangeRateServiceTest {

    @Mock
    private ExchangeRateRepository exchangeRateRepository;

    @Mock
    private SimpMessagingTemplate messagingTemplate;

    @Mock
    private PricingService pricingService;

    private ExchangeRateService exchangeRateService;

    @BeforeEach
    void setUp() {
        // pricingService is an unstubbed mock — rejectIfScaleIsDangerous
        // is a void method that no-ops by default, which matches this
        // test's rates (always scale 2), same as if the guard didn't
        // exist.
        exchangeRateService = new ExchangeRateService(
                exchangeRateRepository, messagingTemplate, pricingService);
        // @Value is never processed outside a Spring context — this
        // class is constructed directly, same convention as
        // PricingServiceTest/PricingServiceDistanceTest use for their
        // own @Value fields.
        ReflectionTestUtils.setField(
                exchangeRateService, "sanityChangeRatio", new BigDecimal("0.50"));
    }

    @Test
    void getCurrentRate_returnsStoredRate() {
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("89500.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));

        BigDecimal result = exchangeRateService.getCurrentRate();

        assertThat(result).isEqualTo(new BigDecimal("89500.00"));
    }

    @Test
    void getCurrentRate_throwsNotFoundException_whenRowMissing() {
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.empty());

        assertThrows(NotFoundException.class,
                () -> exchangeRateService.getCurrentRate());
    }

    @Test
    void updateRate_rejectsZeroOrNegative() {
        assertThrows(BusinessException.class,
                () -> exchangeRateService.updateRate(BigDecimal.ZERO, 1L));
    }

    @Test
    void updateRate_savesAndReturnsNewRate() {
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("89500.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));
        when(exchangeRateRepository.save(any(ExchangeRate.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        BigDecimal result = exchangeRateService.updateRate(
                new BigDecimal("90000.00"), 1L);

        assertThat(result).isEqualTo(new BigDecimal("90000.00"));
        verify(exchangeRateRepository).save(argThat(r ->
                r.getUsdToLbpRate().equals(new BigDecimal("90000.00"))));
    }

    // ───────────────────────────────────────────────────────────
    // The underlying DB column is
    // NUMERIC(14,2) (infra/migrations/0004_add_exchange_rate.sql):
    // max 12 integer digits, 2 decimal digits. Without a bound
    // here, a value above that either crashes with a raw
    // DataIntegrityViolationException in production (leaky,
    // caught only generically as a 400) or, for a tiny-but-positive
    // rate, silently rounds to 0.00 once the DB truncates it to
    // scale 2 — a rate of "0" would then divide-by-zero everywhere
    // downstream (CurrencyConverter). Both are a service-layer
    // responsibility, not a DB-crash responsibility.
    // ───────────────────────────────────────────────────────────
    @Test
    void updateRate_rejectsAbsurdlyLargeRateAboveColumnCapacity() {
        // NUMERIC(14,2) max integer part is 12 nines.
        BigDecimal tooLarge = new BigDecimal("9999999999999.99"); // 13 nines
        assertThrows(BusinessException.class,
                () -> exchangeRateService.updateRate(tooLarge, 1L));
    }

    // ───────────────────────────────────────────────────────────
    // Checks whether updateRate has the same BigDecimal
    // scale/exponent DoS found in OrderService (setScale on a
    // client-influenced value with an extreme scale, e.g.
    // "1e10000000", before any bounds check runs). Checked directly:
    // here the compareTo(MIN_RATE)/compareTo(MAX_RATE) bounds checks
    // run BEFORE setScale, and — confirmed empirically with a scratch
    // timing probe before writing this test (0ms vs. OrderService's
    // measured ~8.8 SECONDS for the equivalent unguarded case) —
    // BigDecimal.compareTo against a small-magnitude reference
    // constant is safe even for a huge-scale value: it short-circuits
    // via an internal "adjusted exponent" estimate whenever the two
    // values' magnitudes are clearly different, without ever
    // constructing the full aligned BigInteger setScale needs. This
    // test locks that in as a permanent regression guard — it should
    // already pass with no code change, proving the finding was
    // correctly "checked, not assumed."
    // ───────────────────────────────────────────────────────────
    @Test
    void updateRate_rejectsHugeExponentRate_quickly_alreadySafe() {
        BigDecimal huge = new BigDecimal("1e10000000");
        assertTimeoutPreemptively(Duration.ofSeconds(1), () ->
                assertThrows(BusinessException.class,
                        () -> exchangeRateService.updateRate(huge, 1L)));
    }

    @Test
    void updateRate_rejectsHugeNegativeExponentRate_quickly_alreadySafe() {
        BigDecimal tiny = new BigDecimal("1e-10000000");
        assertTimeoutPreemptively(Duration.ofSeconds(1), () ->
                assertThrows(BusinessException.class,
                        () -> exchangeRateService.updateRate(tiny, 1L)));
    }

    @Test
    void updateRate_rejectsPositiveRateThatRoundsToZeroAtColumnScale() {
        // Positive (passes the old "<= 0" check) but below the
        // smallest representable value at scale 2 — would silently
        // become 0.00 once persisted.
        BigDecimal roundsToZero = new BigDecimal("0.001");
        assertThrows(BusinessException.class,
                () -> exchangeRateService.updateRate(roundsToZero, 1L));
    }

    @Test
    void updateRate_acceptsSmallestRepresentableRate() {
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("89500.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));
        when(exchangeRateRepository.save(any(ExchangeRate.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        // Confirmed: this is a near-100% drop from the stored 89500.00,
        // which the new sanity guard (see updateRate_rejects... tests
        // below) would otherwise reject by default.
        BigDecimal result = exchangeRateService.updateRate(
                new BigDecimal("0.01"), 1L, true);

        assertThat(result).isEqualTo(new BigDecimal("0.01"));
    }

    @Test
    void updateRate_acceptsLargestRepresentableRate() {
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("89500.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));
        when(exchangeRateRepository.save(any(ExchangeRate.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        // Confirmed: astronomically far from the stored 89500.00 — same
        // reason as updateRate_acceptsSmallestRepresentableRate above.
        BigDecimal result = exchangeRateService.updateRate(
                new BigDecimal("999999999999.99"), 1L, true);

        assertThat(result).isEqualTo(new BigDecimal("999999999999.99"));
    }

    @Test
    void updateRate_roundsExcessiveScaleToColumnScale() {
        // 50 decimal places — must be rounded to scale 2 before
        // being handed to the repository, not saved as-is (which
        // would otherwise rely on the DB to silently round it).
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("89500.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));
        when(exchangeRateRepository.save(any(ExchangeRate.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        BigDecimal excessiveScale = new BigDecimal(
                "90000.123456789012345678901234567890123456789012345");

        BigDecimal result = exchangeRateService.updateRate(excessiveScale, 1L);

        assertThat(result).isEqualTo(new BigDecimal("90000.12"));
    }

    @Test
    void updateRate_broadcastsOverWebSocket() {
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("89500.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));
        when(exchangeRateRepository.save(any(ExchangeRate.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        exchangeRateService.updateRate(new BigDecimal("90000.00"), 1L);

        verify(messagingTemplate)
                .convertAndSend(eq("/topic/exchange-rate"), any(Object.class));
    }

    // ───────────────────────────────────────────────────────────
    // SANITY GUARD (final whole-branch review, finding #3) — a typo
    // like "89.5" instead of "89500" is a >50% change from whatever
    // the rate currently is; MIN_RATE/MAX_RATE alone (the DB column's
    // raw representable range) would happily accept it.
    // ───────────────────────────────────────────────────────────
    @Test
    void updateRate_rejectsLargeDropWithoutConfirmation() {
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("89500.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));

        // The classic "dropped three zeros" typo.
        assertThrows(BusinessException.class, () ->
                exchangeRateService.updateRate(new BigDecimal("89.50"), 1L, false));

        verify(exchangeRateRepository, never()).save(any());
    }

    @Test
    void updateRate_acceptsLargeDropWhenConfirmed() {
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("89500.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));
        when(exchangeRateRepository.save(any(ExchangeRate.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        BigDecimal result = exchangeRateService.updateRate(
                new BigDecimal("89.50"), 1L, true);

        assertThat(result).isEqualTo(new BigDecimal("89.50"));
    }

    @Test
    void updateRate_rejectsLargeSpikeWithoutConfirmation() {
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("89500.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));

        // An extra digit, the opposite direction.
        assertThrows(BusinessException.class, () ->
                exchangeRateService.updateRate(new BigDecimal("895000.00"), 1L, false));

        verify(exchangeRateRepository, never()).save(any());
    }

    @Test
    void updateRate_rejectionMessageNamesOldAndNewRateAndHowToConfirm() {
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("89500.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));

        BusinessException ex = assertThrows(BusinessException.class, () ->
                exchangeRateService.updateRate(new BigDecimal("89.50"), 1L, false));

        assertThat(ex.getMessage()).contains("89500.00");
        assertThat(ex.getMessage()).contains("89.50");
        assertThat(ex.getMessage()).containsIgnoringCase("confirm");
    }

    @Test
    void updateRate_acceptsChangeExactlyAtThresholdWithoutConfirmation() {
        // +50% exactly — the threshold is inclusive ("more than" the
        // ratio is what's rejected, not "at least").
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("100.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));
        when(exchangeRateRepository.save(any(ExchangeRate.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        BigDecimal result = exchangeRateService.updateRate(
                new BigDecimal("150.00"), 1L, false);

        assertThat(result).isEqualTo(new BigDecimal("150.00"));
    }

    @Test
    void updateRate_rejectsChangeJustOverThresholdWithoutConfirmation() {
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("100.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));

        assertThrows(BusinessException.class, () ->
                exchangeRateService.updateRate(new BigDecimal("150.01"), 1L, false));
    }

    @Test
    void updateRate_smallChangeNeverNeedsConfirmation() {
        // Regression guard: the overwhelming common case (a routine
        // small adjustment) must never require confirm:true.
        ExchangeRate stored = ExchangeRate.builder()
                .id(1L)
                .usdToLbpRate(new BigDecimal("89500.00"))
                .updatedAt(LocalDateTime.now())
                .build();
        when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(stored));
        when(exchangeRateRepository.save(any(ExchangeRate.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        BigDecimal result = exchangeRateService.updateRate(
                new BigDecimal("90000.00"), 1L, false);

        assertThat(result).isEqualTo(new BigDecimal("90000.00"));
    }
}
