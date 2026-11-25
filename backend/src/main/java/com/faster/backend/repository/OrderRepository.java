package com.faster.backend.repository;

import com.faster.backend.entity.Order;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface OrderRepository
        extends JpaRepository<Order, Long> {

    // ─── Find order by tracking code ─────────────────
    // Used for O2O tracking link (public endpoint)
    Optional<Order> findByTrackingCode(String trackingCode);

    // ─── All orders for a merchant ────────────────────
    List<Order> findByMerchantIdOrderByCreatedAtDesc(Long merchantId);

    // ─── Active orders for a merchant ─────────────────
    @Query("SELECT o FROM Order o " +
           "WHERE o.merchant.id = :merchantId " +
           "AND o.status NOT IN " +
           "('DELIVERED', 'CANCELLED', 'DISPUTED') " +
           "ORDER BY o.createdAt DESC")
    List<Order> findActiveOrdersByMerchant(
            @Param("merchantId") Long merchantId);

    // ─── All orders for a driver ──────────────────────
    List<Order> findByDriverIdOrderByCreatedAtDesc(Long driverId);

    // ─── Active orders for a driver ───────────────────
    @Query("SELECT o FROM Order o " +
           "WHERE o.driver.id = :driverId " +
           "AND o.status NOT IN " +
           "('DELIVERED', 'CANCELLED', 'DISPUTED')")
    List<Order> findActiveOrdersByDriver(
            @Param("driverId") Long driverId);

    // ─── All orders for a customer ────────────────────
    List<Order> findByCustomerIdOrderByCreatedAtDesc(Long customerId);

    // ─── Find by single status ordered ────────────────
    List<Order> findByStatusOrderByCreatedAtDesc(
            Order.OrderStatus status);

    // ─── Find by multiple statuses ordered ────────────
    // Used by AdminService.getActiveOrders() to return all
    // in-progress orders: PENDING + ACCEPTED + PREPARING
    //                   + READY_FOR_PICKUP + PICKED_UP
    List<Order> findByStatusInOrderByCreatedAtDesc(
            List<Order.OrderStatus> statuses);

    // ─── O2O orders with a suspiciously low manual price ─
    // (M3 fix) — review queue, not a block. See PricingService
    // .validateO2OPrice() and OrderService.createO2OOrder().
    List<Order> findByIsPriceFlaggedTrueOrderByCreatedAtDesc();

    // ─── Orders with a flagged delivery distance ─────────
    // (input-hardening) — review queue, not a block. See
    // PricingService.exceedsMaxDeliveryDistance().
    List<Order> findByIsDistanceFlaggedTrueOrderByCreatedAtDesc();

    // ─── Find pending orders for a merchant ───────────
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

    // ─── Assign driver to order (atomic) ─────────────
    // Only succeeds if order is still PENDING
    // Prevents two drivers accepting the same order
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

    // ─── Cancel order (atomic) ────────────────────────
    // Only succeeds if order is still PENDING — same atomicity
    // guarantee as assignDriver, in the other direction. A plain
    // findById -> in-Java status check -> save() here would race
    // assignDriver: if a driver's accept commits between this
    // transaction's read and its save(), the stale entity's save
    // would silently overwrite the just-committed ACCEPTED status
    // (and driver_id) back to CANCELLED/null.
    @Modifying
    @Query("UPDATE Order o SET o.status = 'CANCELLED', " +
           "o.updatedAt = :now " +
           "WHERE o.id = :orderId " +
           "AND o.status = 'PENDING'")
    int cancelIfPending(
            @Param("orderId") Long orderId,
            @Param("now") LocalDateTime now);

    // ─── Dispute order (atomic) ───────────────────────
    // Same atomicity guarantee as assignDriver/cancelIfPending —
    // disputeOrder's own pre-checks only reject an ALREADY
    // CANCELLED/DISPUTED order from a stale read; this WHERE clause
    // is what actually prevents disputing an order that a concurrent
    // accept/cancel/status-update just changed underneath it.
    @Modifying
    @Query("UPDATE Order o SET o.status = 'DISPUTED', " +
           "o.disputeReason = :reason, " +
           "o.updatedAt = :now " +
           "WHERE o.id = :orderId " +
           "AND o.status NOT IN ('CANCELLED', 'DISPUTED')")
    int disputeIfNotTerminal(
            @Param("orderId") Long orderId,
            @Param("reason") String reason,
            @Param("now") LocalDateTime now);

    // ─── Resolve a dispute (atomic) ───────────────────
    // Only succeeds if the order is still DISPUTED. Used by
    // OrderService.resolveDispute (admin action) so a dispute can
    // only be resolved once, same shape as the other 3 guarded
    // writes above.
    @Modifying
    @Query("UPDATE Order o SET o.status = :resolution, " +
           "o.updatedAt = :now " +
           "WHERE o.id = :orderId " +
           "AND o.status = 'DISPUTED'")
    int resolveIfDisputed(
            @Param("orderId") Long orderId,
            @Param("resolution") Order.OrderStatus resolution,
            @Param("now") LocalDateTime now);

    // ─── Count orders by status for merchant ──────────
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
    BigDecimal sumDriverCommission(
            @Param("driverId") Long driverId,
            @Param("from") LocalDateTime from);

    // ─── Count by status ──────────────────────────────
    long countByStatus(Order.OrderStatus status);

    // ─── Count orders created in a time range ─────────
    long countByCreatedAtBetween(
            LocalDateTime from, LocalDateTime to);

    // ─── Count delivered orders in a time range ───────
    long countByStatusAndDeliveredAtBetween(
            Order.OrderStatus status,
            LocalDateTime from,
            LocalDateTime to);

    // ─── Merchant daily sales total ───────────────────
    @Query("SELECT COALESCE(SUM(o.totalPrice), 0) " +
           "FROM Order o " +
           "WHERE o.merchant.id = :merchantId " +
           "AND o.status = 'DELIVERED' " +
           "AND o.deliveredAt >= :from " +
           "AND o.deliveredAt < :to")
    BigDecimal getMerchantDailySales(
            @Param("merchantId") Long merchantId,
            @Param("from") LocalDateTime from,
            @Param("to") LocalDateTime to);
}