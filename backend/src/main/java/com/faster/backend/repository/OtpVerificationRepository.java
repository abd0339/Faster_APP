package com.faster.backend.repository;

import com.faster.backend.entity.OtpVerification;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface OtpVerificationRepository
        extends JpaRepository<OtpVerification, Long> {

    // ─── Find latest valid OTP for a user ────────────
    Optional<OtpVerification> findTopByUserIdAndIsUsedFalseOrderByCreatedAtDesc(
            Long userId);

    // ─── Delete all OTPs for a user ──────────────────
    // Called before creating a new OTP (one at a time)
    // and after successful verification (cleanup)
    @Modifying
    @Query("DELETE FROM OtpVerification o WHERE o.userId = :userId")
    void deleteAllByUserId(@Param("userId") Long userId);
}