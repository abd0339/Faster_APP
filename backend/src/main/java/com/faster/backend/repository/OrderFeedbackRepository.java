package com.faster.backend.repository;

import com.faster.backend.entity.OrderFeedback;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface OrderFeedbackRepository
        extends JpaRepository<OrderFeedback, Long> {

    // One feedback per order — used to reject duplicate submission
    Optional<OrderFeedback> findByOrderId(Long orderId);
    boolean existsByOrderId(Long orderId);

    // Admin — all feedback, newest first
    List<OrderFeedback> findAllByOrderByCreatedAtDesc();

    // Admin — the queue that actually needs attention:
    // negative feedback not yet resolved
    List<OrderFeedback> findByDriverThumbsUpFalseAndResolvedFalseOrderByCreatedAtAsc();

    // Driver's own average rating — used on driver profile /
    // admin driver detail view. COALESCE avoids returning null
    // when a driver has zero ratings yet.
    @Query("SELECT COALESCE(AVG(f.driverStars), 0) FROM OrderFeedback f " +
           "WHERE f.driverId = :driverId AND f.driverStars IS NOT NULL")
    Double getDriverAverageRating(@Param("driverId") Long driverId);

    @Query("SELECT COUNT(f) FROM OrderFeedback f " +
           "WHERE f.driverId = :driverId AND f.driverStars IS NOT NULL")
    Long getDriverRatingCount(@Param("driverId") Long driverId);

    // Merchant's own average rating — same idea
    @Query("SELECT COALESCE(AVG(f.merchantStars), 0) FROM OrderFeedback f " +
           "WHERE f.merchantId = :merchantId AND f.merchantStars IS NOT NULL")
    Double getMerchantAverageRating(@Param("merchantId") Long merchantId);

    @Query("SELECT COUNT(f) FROM OrderFeedback f " +
           "WHERE f.merchantId = :merchantId AND f.merchantStars IS NOT NULL")
    Long getMerchantRatingCount(@Param("merchantId") Long merchantId);
}