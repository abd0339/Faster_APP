package com.faster.backend.service;

import com.faster.backend.dto.AdminStatsResponse;
import com.faster.backend.dto.AdminUserResponse;
import com.faster.backend.entity.LedgerEntry;
import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.exception.NotFoundException;
import com.faster.backend.repository.LedgerRepository;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Sort;
import org.springframework.messaging.simp.SimpMessagingTemplate;
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
    private final OrderService orderService;
    private final SimpMessagingTemplate messagingTemplate;

    // See LedgerService's identical constant for why this must be
    // explicit — the JVM's default zone is UTC, not Beirut.
    private static final java.time.ZoneId BEIRUT =
            java.time.ZoneId.of("Asia/Beirut");

    // ─────────────────────────────────────────────────
    // PLATFORM STATS — Full dashboard overview
    // ─────────────────────────────────────────────────
    public AdminStatsResponse getPlatformStats() {

        // FIX: the comment here used to claim "Asia/Beirut handled by
        // app timezone", but nothing in the repo actually sets the
        // JVM's default zone (confirmed UTC) — an unzoned LocalDate.now()
        // silently used UTC's calendar day, undercounting "today" for
        // the first ~2 hours after Beirut midnight. Same bug and fix as
        // LedgerService's scheduled jobs.
        LocalDateTime startOfDay =
                LocalDate.now(BEIRUT).atStartOfDay();
        LocalDateTime endOfDay =
                LocalDate.now(BEIRUT).atTime(LocalTime.MAX);

        // ─── User counts ──────────────────────────────
        long totalUsers    = userRepository.count();
        long totalMerchants = userRepository.countByRole(User.Role.MERCHANT);
        long totalDrivers  = userRepository.countByRole(User.Role.DRIVER);
        long totalCustomers = userRepository.countByRole(User.Role.CUSTOMER);
        long blockedDrivers = userRepository.countByIsBlockedTrue();
        long activeDrivers  = userRepository.countByIsOnlineTrue();

        // ─── Order counts ─────────────────────────────
        long totalOrders   = orderRepository.count();
        long pendingOrders = orderRepository.countByStatus(
                Order.OrderStatus.PENDING);

        // Active = all in-progress statuses
        // (not just PENDING — that is waiting for driver)
        long activeOrders = orderRepository.countByStatusIn(List.of(
                Order.OrderStatus.ACCEPTED,
                Order.OrderStatus.PREPARING,
                Order.OrderStatus.READY_FOR_PICKUP,
                Order.OrderStatus.PICKED_UP));

        long deliveredOrders = orderRepository.countByStatus(
                Order.OrderStatus.DELIVERED);
        long disputedOrders  = orderRepository.countByStatus(
                Order.OrderStatus.DISPUTED);
        long cancelledOrders = orderRepository.countByStatus(
                Order.OrderStatus.CANCELLED);

        // ─── Today's activity ─────────────────────────
        long todayOrders = orderRepository.countByCreatedAtBetween(
                startOfDay, endOfDay);
        long todayDeliveries = orderRepository
                .countByStatusAndDeliveredAtBetween(
                        Order.OrderStatus.DELIVERED,
                        startOfDay, endOfDay);

        // ─── Financial ────────────────────────────────
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
                        ? totalRevenue : BigDecimal.ZERO)
                .todayRevenue(
                        todayRevenue != null
                        ? todayRevenue : BigDecimal.ZERO)
                .todayOrders(todayOrders)
                .todayDeliveries(todayDeliveries)
                .build();
    }

    // ─────────────────────────────────────────────────
    // USER MANAGEMENT
    // ─────────────────────────────────────────────────

    public List<AdminUserResponse> getAllUsers() {
        return mapUsers(userRepository.findAll());
    }

    public List<AdminUserResponse> getUsersByRole(User.Role role) {
        return mapUsers(userRepository.findByRole(role));
    }

    public List<AdminUserResponse> getAllDrivers() {
        return mapUsers(userRepository.findByRole(User.Role.DRIVER));
    }

    public List<AdminUserResponse> getBlockedDrivers() {
        return mapUsers(
                userRepository.findByRoleAndIsBlockedTrue(User.Role.DRIVER));
    }

    // FIX: this used to live only in AdminController.getPendingDrivers,
    // querying userRepository directly instead of going through this
    // service like every sibling endpoint — easy to miss when changing
    // how a User is projected into AdminUserResponse, since it doesn't
    // look like the others.
    public List<AdminUserResponse> getPendingDrivers() {
        return mapUsers(userRepository.findByRoleAndVerificationStatus(
                User.Role.DRIVER, User.DriverVerificationStatus.SUBMITTED));
    }

    private List<AdminUserResponse> mapUsers(List<User> users) {
        return users.stream()
                .map(AdminUserResponse::from)
                .collect(Collectors.toList());
    }

    public AdminUserResponse getUserById(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new NotFoundException("User not found"));
        return AdminUserResponse.from(user);
    }

    // ─── Block user manually ──────────────────────────
    // Admin decides when to block — no auto-block in this system
    @Transactional
    public AdminUserResponse blockUser(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new NotFoundException("User not found"));
        user.setIsBlocked(true);
        userRepository.save(user);

        // FIX: driver_dashboard_screen.dart already has a handler for a
        // "BLOCKED" message on /topic/driver/{id} (stops the GPS stream,
        // disconnects, shows "Account paused") — nothing on the backend
        // ever sent one, so a driver blocked while already online and
        // connected got no proactive signal; the block was only
        // discovered the next time they tried to accept an order.
        if (user.getRole() == User.Role.DRIVER) {
            messagingTemplate.convertAndSend(
                    "/topic/driver/" + userId,
                    java.util.Map.of("type", "BLOCKED"));
        }

        return AdminUserResponse.from(user);
    }

    // ─── Unblock user manually ────────────────────────
    @Transactional
    public AdminUserResponse unblockUser(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new NotFoundException("User not found"));
        user.setIsBlocked(false);
        userRepository.save(user);
        return AdminUserResponse.from(user);
    }

    // ─── Deactivate user account ──────────────────────
    @Transactional
    public AdminUserResponse deactivateUser(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new NotFoundException("User not found"));
        user.setIsActive(false);
        userRepository.save(user);
        return AdminUserResponse.from(user);
    }

    // ─────────────────────────────────────────────────
    // ORDER MANAGEMENT
    // ─────────────────────────────────────────────────

    public List<Order> getAllOrders() {
        return orderRepository.findAll(
                Sort.by(Sort.Direction.DESC, "createdAt"));
    }

    public List<Order> getDisputedOrders() {
        return orderRepository.findByStatusOrderByCreatedAtDesc(
                Order.OrderStatus.DISPUTED);
    }

    // ─── O2O orders with a suspiciously low manual price ─
    // (M3 fix) — review queue, not a block.
    public List<Order> getPriceFlaggedOrders() {
        return orderRepository.findByIsPriceFlaggedTrueOrderByCreatedAtDesc();
    }

    // ─── Orders with a flagged delivery distance ──────────
    // (input-hardening) — review queue, not a block.
    public List<Order> getDistanceFlaggedOrders() {
        return orderRepository.findByIsDistanceFlaggedTrueOrderByCreatedAtDesc();
    }

    // ─── All in-progress orders ───────────────────────
    // Returns PENDING + ACCEPTED + PREPARING +
    //         READY_FOR_PICKUP + PICKED_UP
    // These are all orders that are not yet completed/cancelled
    public List<Order> getActiveOrders() {
        return orderRepository.findByStatusInOrderByCreatedAtDesc(
                List.of(
                        Order.OrderStatus.PENDING,
                        Order.OrderStatus.ACCEPTED,
                        Order.OrderStatus.PREPARING,
                        Order.OrderStatus.READY_FOR_PICKUP,
                        Order.OrderStatus.PICKED_UP));
    }

    // ─── Resolve dispute ──────────────────────────────
    // FIX: this used to set the status directly with no
    // state-machine check, no commission recording, and no
    // broadcast — delegates to OrderService.resolveDispute, which
    // owns all of an order's lifecycle side effects (ledger,
    // WebSocket, push), instead of re-implementing a slice of them
    // here with none of the same guarantees.
    public Order resolveDispute(Long orderId,
                                Order.OrderStatus resolution) {
        return orderService.resolveDispute(orderId, resolution);
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
                driverId, amount, paymentReference, adminId);
    }

    // ─── Settle merchant commission ───────────────────
    @Transactional
    public LedgerEntry settleMerchantCommission(
            Long merchantId,
            BigDecimal amount,
            String paymentReference,
            Long adminId) {
        return ledgerService.settleMerchantCommission(
                merchantId, amount, paymentReference, adminId);
    }

    // ─── Get driver debt details ──────────────────────
    public AdminUserResponse getDriverDebtDetails(Long driverId) {
        User driver = userRepository.findById(driverId)
                .orElseThrow(() -> new NotFoundException(
                        "Driver not found"));
        return AdminUserResponse.from(driver);
    }

    // ─── Get full platform ledger ─────────────────────
    public List<LedgerEntry> getFullLedger() {
        return ledgerRepository.findAll(
                Sort.by(Sort.Direction.DESC, "createdAt"));
    }

    // ─── Get all driver commission entries ────────────
    public List<LedgerEntry> getAllDriverCommissions() {
        return ledgerRepository.findAllDriverCommissions();
    }
}