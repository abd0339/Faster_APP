package com.faster.backend.repository;

import com.faster.backend.entity.StoreSchedule;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface StoreScheduleRepository
        extends JpaRepository<StoreSchedule, Long> {

    // ─── Full weekly schedule for a merchant ─────────
    List<StoreSchedule> findByMerchantIdOrderByDayOfWeekAsc(
            Long merchantId);

    // ─── Schedule for a specific day ─────────────────
    Optional<StoreSchedule> findByMerchantIdAndDayOfWeek(
            Long merchantId,
            StoreSchedule.DayOfWeek dayOfWeek);

    // ─── Is the store open today? ────────────────────
    @Query("SELECT s FROM StoreSchedule s " +
           "WHERE s.merchant.id = :merchantId " +
           "AND s.dayOfWeek = :day " +
           "AND s.isClosed = false")
    Optional<StoreSchedule> findOpenSchedule(
            @Param("merchantId") Long merchantId,
            @Param("day") StoreSchedule.DayOfWeek day);

    // ─── Check if schedule exists for this day ───────
    boolean existsByMerchantIdAndDayOfWeek(
            Long merchantId,
            StoreSchedule.DayOfWeek dayOfWeek);
}