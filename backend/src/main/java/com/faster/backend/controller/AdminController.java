package com.faster.backend.controller;

import com.faster.backend.dto.AdminStatsResponse;
import com.faster.backend.dto.AdminUserResponse;
import com.faster.backend.dto.DebtSettlementRequest;
import com.faster.backend.entity.LedgerEntry;
import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.AdminService;
import com.faster.backend.service.LedgerService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
public class AdminController {

    private final AdminService adminService;
    private final LedgerService ledgerService;
    private final UserRepository userRepository;

    // ─────────────────────────────────────────────────
    // DASHBOARD STATS
    // ─────────────────────────────────────────────────

    // GET /api/admin/stats
    @GetMapping("/stats")
    public ResponseEntity<AdminStatsResponse> getStats() {
        return ResponseEntity.ok(
                adminService.getPlatformStats());
    }

    // GET /api/admin/revenue
    @GetMapping("/revenue")
    public ResponseEntity<?> getRevenue(
            @RequestParam(required = false) LocalDateTime from,
            @RequestParam(required = false) LocalDateTime to) {
        return ResponseEntity.ok(
                ledgerService.getPlatformRevenue(
                        from, to));
    }

    // ─────────────────────────────────────────────────
    // USER MANAGEMENT
    // ─────────────────────────────────────────────────

    // GET /api/admin/users
    @GetMapping("/users")
    public ResponseEntity<List<AdminUserResponse>> getAllUsers() {
        return ResponseEntity.ok(
                adminService.getAllUsers());
    }

    // GET /api/admin/users/{id}
    @GetMapping("/users/{id}")
    public ResponseEntity<AdminUserResponse> getUser(@PathVariable Long id) {
        return ResponseEntity.ok(
                adminService.getUserById(id));
    }

    // GET /api/admin/drivers
    @GetMapping("/drivers")
    public ResponseEntity<List<AdminUserResponse>> getAllDrivers() {
        return ResponseEntity.ok(
                adminService.getAllDrivers());
    }

    // GET /api/admin/drivers/blocked
    @GetMapping("/drivers/blocked")
    public ResponseEntity<List<AdminUserResponse>> getBlockedDrivers() {
        return ResponseEntity.ok(
                adminService.getBlockedDrivers());
    }

    // GET /api/admin/merchants
    @GetMapping("/merchants")
    public ResponseEntity<List<AdminUserResponse>> getAllMerchants() {
        return ResponseEntity.ok(
                adminService.getUsersByRole(
                        User.Role.MERCHANT));
    }

    // PATCH /api/admin/users/{id}/block
    @PatchMapping("/users/{id}/block")
    public ResponseEntity<?> blockUser(
            @PathVariable Long id) {
        AdminUserResponse user = adminService.blockUser(id);
        return ResponseEntity.ok(Map.of(
                "message", "User blocked successfully",
                "user", user));
    }

    // PATCH /api/admin/users/{id}/unblock
    @PatchMapping("/users/{id}/unblock")
    public ResponseEntity<?> unblockUser(
            @PathVariable Long id) {
        AdminUserResponse user = adminService.unblockUser(id);
        return ResponseEntity.ok(Map.of(
                "message", "User unblocked successfully",
                "user", user));
    }

    // PATCH /api/admin/users/{id}/deactivate
    @PatchMapping("/users/{id}/deactivate")
    public ResponseEntity<?> deactivateUser(
            @PathVariable Long id) {
        AdminUserResponse user = adminService.deactivateUser(id);
        return ResponseEntity.ok(Map.of(
                "message", "User deactivated successfully",
                "user", user));
    }

    // ─────────────────────────────────────────────────
    // ORDER MANAGEMENT
    // ─────────────────────────────────────────────────

    // GET /api/admin/orders
    @GetMapping("/orders")
    public ResponseEntity<List<Order>> getAllOrders() {
        return ResponseEntity.ok(
                adminService.getAllOrders());
    }

    // GET /api/admin/orders/disputed
    @GetMapping("/orders/disputed")
    public ResponseEntity<List<Order>> getDisputedOrders() {
        return ResponseEntity.ok(
                adminService.getDisputedOrders());
    }

    // GET /api/admin/orders/active
    @GetMapping("/orders/active")
    public ResponseEntity<List<Order>> getActiveOrders() {
        return ResponseEntity.ok(
                adminService.getActiveOrders());
    }

    // PATCH /api/admin/orders/{id}/resolve
    @PatchMapping("/orders/{id}/resolve")
    public ResponseEntity<?> resolveDispute(
            @PathVariable Long id,
            @RequestParam Order.OrderStatus resolution) {
        Order order = adminService
                .resolveDispute(id, resolution);
        return ResponseEntity.ok(Map.of(
                "message", "Dispute resolved",
                "orderId", order.getId(),
                "newStatus", order.getStatus()));
    }

    // ─────────────────────────────────────────────────
    // FINANCIAL MANAGEMENT
    // ─────────────────────────────────────────────────

    // GET /api/admin/ledger
    @GetMapping("/ledger")
    public ResponseEntity<List<LedgerEntry>> getFullLedger() {
        return ResponseEntity.ok(
                adminService.getFullLedger());
    }

    // GET /api/admin/ledger/driver/{id}
    @GetMapping("/ledger/driver/{id}")
    public ResponseEntity<?> getDriverLedger(
            @PathVariable Long id) {
        return ResponseEntity.ok(
                ledgerService.getDriverLedger(id)
                        .stream()
                        .map(com.faster.backend.dto.LedgerResponse::from)
                        .collect(java.util.stream.Collectors.toList()));
    }

    // GET /api/admin/ledger/merchant/{id}
    @GetMapping("/ledger/merchant/{id}")
    public ResponseEntity<?> getMerchantLedger(
            @PathVariable Long id) {
        return ResponseEntity.ok(
                ledgerService.getMerchantLedger(id)
                        .stream()
                        .map(com.faster.backend.dto.LedgerResponse::from)
                        .collect(java.util.stream.Collectors.toList()));
    }

    // GET /api/admin/drivers/{id}/debt
    @GetMapping("/drivers/{id}/debt")
    public ResponseEntity<?> getDriverDebt(
            @PathVariable Long id) {
        return ResponseEntity.ok(
                ledgerService.getDriverDebtSummary(id));
    }

    // PATCH /api/admin/drivers/{id}/settle
    // Admin confirms driver paid their commission
    @PatchMapping("/drivers/{id}/settle")
    public ResponseEntity<?> settleDriverDebt(
            @PathVariable Long id,
            @Valid @RequestBody DebtSettlementRequest request,
            Authentication auth) {

        Long adminId = getAdminId(auth);

        LedgerEntry entry = adminService
                .settleDriverDebt(
                        id,
                        request.getAmount(),
                        request.getPaymentReference(),
                        adminId);

        return ResponseEntity.ok(Map.of(
                "message",
                "Driver debt settled successfully. " +
                        "Account reactivated.",
                "amountPaid", entry.getAmount(),
                "remainingDebt", entry.getBalanceAfter(),
                "paymentReference",
                entry.getPaymentReference()));
    }

    // PATCH /api/admin/merchants/{id}/settle
    // Admin confirms merchant paid commission
    @PatchMapping("/merchants/{id}/settle")
    public ResponseEntity<?> settleMerchantCommission(
            @PathVariable Long id,
            @Valid @RequestBody DebtSettlementRequest request,
            Authentication auth) {

        Long adminId = getAdminId(auth);

        LedgerEntry entry = adminService
                .settleMerchantCommission(
                        id,
                        request.getAmount(),
                        request.getPaymentReference(),
                        adminId);

        return ResponseEntity.ok(Map.of(
                "message",
                "Merchant commission settled.",
                "amountPaid", entry.getAmount(),
                "remainingBalance", entry.getBalanceAfter(),
                "paymentReference",
                entry.getPaymentReference()));
    }

    // ─── Helper ───────────────────────────────────────
    private Long getAdminId(Authentication auth) {
        String principal = auth.getName();
        User user = userRepository
                .findByEmail(principal)
                .orElseGet(() -> userRepository.findByPhone(principal)
                        .orElseThrow(() -> new RuntimeException(
                                "Admin not found")));
        return user.getId();
    }

    // ─── GET /api/admin/drivers/pending ──────────────────
    // Admin sees drivers waiting for verification
    @GetMapping("/drivers/pending")
    public ResponseEntity<?> getPendingDrivers() {
        return ResponseEntity.ok(
                userRepository
                        .findByRoleAndVerificationStatus(
                                User.Role.DRIVER,
                                User.DriverVerificationStatus.SUBMITTED)
                        .stream()
                        .map(AdminUserResponse::from)
                        .collect(java.util.stream.Collectors.toList()));
    }

    // ─── PATCH /api/admin/drivers/{id}/approve ───────────
    @PatchMapping("/drivers/{id}/approve")
    public ResponseEntity<?> approveDriver(
            @PathVariable Long id) {
        User driver = userRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Driver not found"));
        driver.setVerificationStatus(
                User.DriverVerificationStatus.APPROVED);
        userRepository.save(driver);
        return ResponseEntity.ok(Map.of(
                "message", "Driver approved successfully",
                "driverId", id));
    }

    // ─── PATCH /api/admin/drivers/{id}/reject ────────────
    @PatchMapping("/drivers/{id}/reject")
    public ResponseEntity<?> rejectDriver(
            @PathVariable Long id,
            @RequestParam String reason) {
        User driver = userRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Driver not found"));
        driver.setVerificationStatus(
                User.DriverVerificationStatus.REJECTED);
        userRepository.save(driver);
        return ResponseEntity.ok(Map.of(
                "message", "Driver rejected",
                "reason", reason));
    }
}