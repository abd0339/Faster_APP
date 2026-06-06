package com.faster.backend.repository;

import com.faster.backend.entity.Order;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface OrderRepository
        extends JpaRepository<Order, Long> {

    // ─── Find order by tracking code ─────────────────
    // Used for O2O tracking link
    Optional<Order> findByTrackingCode(
            String trackingCode);

    // ─── All orders for a merchant ────────────────────
    List<Order> findByMerchantIdOrderByCreatedAtDesc(
            Long merchantId);

    // ─── Active orders for a merchant ────────────────
    @Query("SELECT o FROM Order o " +
           "WHERE o.merchant.id = :merchantId " +
           "AND o.status NOT IN " +
           "('DELIVERED', 'CANCELLED', 'DISPUTED') " +
           "ORDER BY o.createdAt DESC")
    List<Order> findActiveOrdersByMerchant(
            @Param("merchantId") Long merchantId);

    // ─── All orders for a driver ──────────────────────
    List<Order> findByDriverIdOrderByCreatedAtDesc(
            Long driverId);

    // ─── Active orders for a driver ──────────────────
    @Query("SELECT o FROM Order o " +
           "WHERE o.driver.id = :driverId " +
           "AND o.status NOT IN " +
           "('DELIVERED', 'CANCELLED', 'DISPUTED')")
    List<Order> findActiveOrdersByDriver(
            @Param("driverId") Long driverId);

    // ─── All orders for a customer ────────────────────
    List<Order> findByCustomerIdOrderByCreatedAtDesc(
            Long customerId);

    // ─── Find pending orders (waiting for driver) ─────
    @Query("SELECT o FROM Order o " +
           "WHERE o.status = 'PENDING' " +
           "AND o.merchant.id = :merchantId " +
           "ORDER BY o.createdAt ASC")
    List<Order> findPendingOrdersByMerchant(
            @Param("merchantId") Long merchantId);

    // ─── Update order status ──────────────────────────
    @Modifying
    @Query("UPDATE Order o SET o.status = :status, " +
           "o.updatedAt = :now " +
           "WHERE o.id = :orderId")
    int updateOrderStatus(
            @Param("orderId") Long orderId,
            @Param("status") Order.OrderStatus status,
            @Param("now") LocalDateTime now);

    // ─── Assign driver to order ───────────────────────
    @Modifying
    @Query("UPDATE Order o SET o.driver.id = :driverId, " +
           "o.status = 'ACCEPTED', " +
           "o.acceptedAt = :now, " +
           "o.updatedAt = :now " +
           "WHERE o.id = :orderId " +
           "AND o.status = 'PENDING'")
    int assignDriver(
            @Param("orderId") Long orderId,
            @Param("driverId") Long driverId,
            @Param("now") LocalDateTime now);

    // ─── Count orders by status for merchant ─────────
    @Query("SELECT COUNT(o) FROM Order o " +
           "WHERE o.merchant.id = :merchantId " +
           "AND o.status = :status")
    long countByMerchantAndStatus(
            @Param("merchantId") Long merchantId,
            @Param("status") Order.OrderStatus status);

    // ─── Driver earnings query ────────────────────────
    @Query("SELECT SUM(o.commissionAmount) FROM Order o " +
           "WHERE o.driver.id = :driverId " +
           "AND o.status = 'DELIVERED' " +
           "AND o.deliveredAt >= :from")
    java.math.BigDecimal sumDriverCommission(
            @Param("driverId") Long driverId,
            @Param("from") LocalDateTime from);
}