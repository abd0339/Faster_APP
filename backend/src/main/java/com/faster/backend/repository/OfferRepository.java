package com.faster.backend.repository;

import com.faster.backend.entity.Offer;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface OfferRepository
        extends JpaRepository<Offer, Long> {

    // ─── All active offers for a merchant ────────────
    List<Offer> findByMerchantIdAndIsActiveTrueOrderByCreatedAtDesc(
            Long merchantId);

    // ─── All offers (active + inactive) for merchant ─
    List<Offer> findByMerchantIdOrderByCreatedAtDesc(
            Long merchantId);

    // ─── Find one offer belonging to a merchant ───────
    Optional<Offer> findByIdAndMerchantId(
            Long id, Long merchantId);

    // ─── Currently live offers (within date window) ──
    // Used for customer-facing offer banner display
    @Query("SELECT o FROM Offer o " +
           "WHERE o.merchant.id = :merchantId " +
           "AND o.isActive = true " +
           "AND (o.startDate IS NULL OR o.startDate <= :now) " +
           "AND (o.endDate IS NULL OR o.endDate >= :now) " +
           "ORDER BY o.createdAt DESC")
    List<Offer> findLiveOffers(
            @Param("merchantId") Long merchantId,
            @Param("now") LocalDateTime now);

    // ─── Auto-expire offers past their end date ───────
    @Modifying
    @Query("UPDATE Offer o SET o.isActive = false " +
           "WHERE o.isActive = true " +
           "AND o.endDate IS NOT NULL " +
           "AND o.endDate < :now")
    int expireOldOffers(@Param("now") LocalDateTime now);

    // ─── Increment usage count when offer is applied ─
    @Modifying
    @Query("UPDATE Offer o SET o.usageCount = o.usageCount + 1 " +
           "WHERE o.id = :offerId")
    int incrementUsageCount(@Param("offerId") Long offerId);
}