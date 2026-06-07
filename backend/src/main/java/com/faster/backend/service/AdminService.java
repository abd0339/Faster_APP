package com.faster.backend.service;

import com.faster.backend.dto.AdminStatsResponse;
import com.faster.backend.dto.AdminUserResponse;
import com.faster.backend.entity.LedgerEntry;
import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.repository.LedgerRepository;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class AdminService {

    private final UserRepository userRepository;
    private final OrderRepository orderRepository;
    private final LedgerRepository ledgerRepository;
    private final LedgerService ledgerService;

    // ─────────────────────────────────────────────────
    // PLATFORM STATS — Full dashboard overview
    // ─────────────────────────────────────────────────
    public AdminStatsResponse getPlatformStats() {

        // Today range
        LocalDateTime startOfDay =
            LocalDate.now().atStartOfDay();
        LocalDateTime endOfDay =
            LocalDate.now().atTime(LocalTime.MAX);

        // User counts
        long totalUsers =
            userRepository.count();
        long totalMerchants =
            userRepository.countByRole(
                User.Role.MERCHANT);
        long totalDrivers =
            userRepository.countByRole(
                User.Role.DRIVER);
        long totalCustomers =
            userRepository.countByRole(
                User.Role.CUSTOMER);
        long blockedDrivers =
            userRepository.countByIsBlockedTrue();
        long activeDrivers =
            userRepository.countByIsOnlineTrue();

        // Order counts
        long totalOrders =
            orderRepository.count();
        long pendingOrders =
            orderRepository.countByStatus(
                Order.OrderStatus.PENDING);
        long activeOrders =
            orderRepository.countByStatus(
                Order.OrderStatus.ACCEPTED)
            + orderRepository.countByStatus(
                Order.OrderStatus.PREPARING)
            + orderRepository.countByStatus(
                Order.OrderStatus.PICKED_UP);
        long deliveredOrders =
            orderRepository.countByStatus(
                Order.OrderStatus.DELIVERED);
        long disputedOrders =
            orderRepository.countByStatus(
                Order.OrderStatus.DISPUTED);
        long cancelledOrders =
            orderRepository.countByStatus(
                Order.OrderStatus.CANCELLED);

        // Today's orders
        long todayOrders =
            orderRepository.countByCreatedAtBetween(
                startOfDay, endOfDay);
        long todayDeliveries =
            orderRepository
                .countByStatusAndDeliveredAtBetween(
                    Order.OrderStatus.DELIVERED,
                    startOfDay, endOfDay);

        // Financial
        BigDecimal totalRevenue =
            ledgerRepository.getPlatformTotalRevenue();
        BigDecimal todayRevenue =
            ledgerRepository.getPlatformRevenueInRange(
                startOfDay, endOfDay);

        return AdminStatsResponse.builder()
                .totalUsers(totalUsers)
                .totalMerchants(totalMerchants)
                .totalDrivers(totalDrivers)
                .totalCustomers(totalCustomers)
                .blockedDrivers(blockedDrivers)
                .activeDrivers(activeDrivers)
                .totalOrders(totalOrders)
                .pendingOrders(pendingOrders)
                .activeOrders(activeOrders)
                .deliveredOrders(deliveredOrders)
                .disputedOrders(disputedOrders)
                .cancelledOrders(cancelledOrders)
                .totalPlatformRevenue(
                    totalRevenue != null
                    ? totalRevenue
                    : BigDecimal.ZERO)
                .todayRevenue(
                    todayRevenue != null
                    ? todayRevenue
                    : BigDecimal.ZERO)
                .todayOrders(todayOrders)
                .todayDeliveries(todayDeliveries)
                .build();
    }

    // ─────────────────────────────────────────────────
    // USER MANAGEMENT
    // ─────────────────────────────────────────────────

    public List<AdminUserResponse> getAllUsers() {
        return userRepository.findAll()
                .stream()
                .map(AdminUserResponse::from)
                .collect(Collectors.toList());
    }

    public List<AdminUserResponse> getUsersByRole(
            User.Role role) {
        return userRepository.findByRole(role)
                .stream()
                .map(AdminUserResponse::from)
                .collect(Collectors.toList());
    }

    public List<AdminUserResponse> getAllDrivers() {
        return userRepository
                .findByRole(User.Role.DRIVER)
                .stream()
                .map(AdminUserResponse::from)
                .collect(Collectors.toList());
    }

    public List<AdminUserResponse> getBlockedDrivers() {
        return userRepository
                .findByRoleAndIsBlockedTrue(
                    User.Role.DRIVER)
                .stream()
                .map(AdminUserResponse::from)
                .collect(Collectors.toList());
    }

    public AdminUserResponse getUserById(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() ->
                    new RuntimeException(
                        "User not found"));
        return AdminUserResponse.from(user);
    }

    // ─── Block user manually ──────────────────────────
    @Transactional
    public AdminUserResponse blockUser(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() ->
                    new RuntimeException(
                        "User not found"));
        user.setIsBlocked(true);
        userRepository.save(user);
        return AdminUserResponse.from(user);
    }

    // ─── Unblock user manually ────────────────────────
    @Transactional
    public AdminUserResponse unblockUser(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() ->
                    new RuntimeException(
                        "User not found"));
        user.setIsBlocked(false);
        userRepository.save(user);
        return AdminUserResponse.from(user);
    }

    // ─── Deactivate user account ──────────────────────
    @Transactional
    public AdminUserResponse deactivateUser(
            Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() ->
                    new RuntimeException(
                        "User not found"));
        user.setIsActive(false);
        userRepository.save(user);
        return AdminUserResponse.from(user);
    }

    // ─────────────────────────────────────────────────
    // ORDER MANAGEMENT
    // ─────────────────────────────────────────────────

    public List<Order> getAllOrders() {
        return orderRepository
            .findAll(
                org.springframework.data.domain
                    .Sort.by(
                        org.springframework.data
                            .domain.Sort.Direction.DESC,
                        "createdAt"));
    }

    public List<Order> getDisputedOrders() {
        return orderRepository
            .findByStatusOrderByCreatedAtDesc(
                Order.OrderStatus.DISPUTED);
    }

    public List<Order> getActiveOrders() {
        return orderRepository
            .findByStatusOrderByCreatedAtDesc(
                Order.OrderStatus.PENDING);
    }

    // ─── Resolve dispute ──────────────────────────────
    @Transactional
    public Order resolveDispute(Long orderId,
                                Order.OrderStatus resolution) {
        Order order = orderRepository
                .findById(orderId)
                .orElseThrow(() ->
                    new RuntimeException(
                        "Order not found"));

        if (order.getStatus() !=
                Order.OrderStatus.DISPUTED) {
            throw new RuntimeException(
                "Order is not in disputed state");
        }

        order.setStatus(resolution);
        return orderRepository.save(order);
    }

    // ─────────────────────────────────────────────────
    // FINANCIAL MANAGEMENT
    // ─────────────────────────────────────────────────

    // ─── Settle driver debt ───────────────────────────
    @Transactional
    public LedgerEntry settleDriverDebt(
            Long driverId,
            BigDecimal amount,
            String paymentReference,
            Long adminId) {
        return ledgerService.settleDriverDebt(
            driverId, amount,
            paymentReference, adminId);
    }

    // ─── Settle merchant commission ───────────────────
    @Transactional
    public LedgerEntry settleMerchantCommission(
            Long merchantId,
            BigDecimal amount,
            String paymentReference,
            Long adminId) {
        return ledgerService.settleMerchantCommission(
            merchantId, amount,
            paymentReference, adminId);
    }

    // ─── Get driver debt details ──────────────────────
    public AdminUserResponse getDriverDebtDetails(
            Long driverId) {
        User driver = userRepository
                .findById(driverId)
                .orElseThrow(() ->
                    new RuntimeException(
                        "Driver not found"));
        return AdminUserResponse.from(driver);
    }

    // ─── Get full platform ledger ─────────────────────
    public List<LedgerEntry> getFullLedger() {
        return ledgerRepository.findAll(
            org.springframework.data.domain
                .Sort.by(
                    org.springframework.data
                        .domain.Sort.Direction.DESC,
                    "createdAt"));
    }

    // ─── Get all driver commission entries ────────────
    public List<LedgerEntry> getAllDriverCommissions() {
        return ledgerRepository
            .findAllDriverCommissions();
    }
}