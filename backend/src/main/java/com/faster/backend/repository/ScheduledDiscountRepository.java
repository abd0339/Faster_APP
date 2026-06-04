package com.faster.backend.repository;

import com.faster.backend.entity.ScheduledDiscount;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface ScheduledDiscountRepository
        extends JpaRepository<ScheduledDiscount, Long> {

    // ─── All discounts for an item ────────────────────
    List<ScheduledDiscount> findByItemIdAndIsActiveTrue(
            Long itemId);

    // ─── Find active discount for item at current time ─
    // Used to calculate real-time price for customers
    @Query("SELECT d FROM ScheduledDiscount d " +
           "WHERE d.item.id = :itemId " +
           "AND d.isActive = true " +
           "AND d.startTime <= :now " +
           "AND d.endTime >= :now " +
           "AND d.daysOfWeek LIKE CONCAT('%', :day, '%')")
    Optional<ScheduledDiscount> findActiveDiscountNow(
            @Param("itemId") Long itemId,
            @Param("now") LocalTime now,
            @Param("day") String day);

    // ─── Verify discount belongs to merchant ─────────
    @Query("SELECT d FROM ScheduledDiscount d " +
           "WHERE d.id = :discountId " +
           "AND d.item.merchant.id = :merchantId")
    Optional<ScheduledDiscount> findByIdAndMerchantId(
            @Param("discountId") Long discountId,
            @Param("merchantId") Long merchantId);
}