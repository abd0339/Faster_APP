package com.faster.backend.repository;

import com.faster.backend.entity.User;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.List;

@Repository
public interface UserRepository extends JpaRepository<User, Long> {

    // ─── Locked fetch — serializes concurrent read-modify-write on
    // a single user's balance fields (debtAmount for drivers, or
    // just as a per-merchant mutex around ledger balance
    // recalculation). Holds the row lock until the caller's
    // @Transactional method commits. See LedgerService — this is
    // what makes recordDriverCommission/settleDriverDebt and
    // recordMerchantDailyCommission/settleMerchantCommission safe
    // against concurrent calls for the same user.
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT u FROM User u WHERE u.id = :id")
    Optional<User> findByIdForUpdate(@Param("id") Long id);

    // ─── Find a user by their : ──────────
    // Used during login to check if the phone exists
    Optional<User> findByPhone(String phone);

    // ─── Check if a phone number is already taken ───
    boolean existsByPhone(String phone);

    // Check if email is already taken during registration
    boolean existsByEmail(String email);

    // Find user by email (for future email login option)
    Optional<User> findByEmail(String email);

    // ─── Find all active users by role ───────────────
    // Used by LedgerService daily merchant commission job
    List<User> findByRoleAndIsActiveTrue(User.Role role);

    // ─── Find users by role ───────────────────────────
    List<User> findByRole(User.Role role);

    // ─── Count by role ────────────────────────────────
    long countByRole(User.Role role);

    // ─── Count blocked drivers ────────────────────────
    long countByIsBlockedTrue();

    // ─── Count online drivers ─────────────────────────
    long countByIsOnlineTrue();

    // ─── Find blocked drivers ─────────────────────────
    List<User> findByRoleAndIsBlockedTrue(
            User.Role role);
            
    List<User> findByRoleAndVerificationStatus(
    User.Role role,
    User.DriverVerificationStatus status);

}