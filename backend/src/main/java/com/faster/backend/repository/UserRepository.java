package com.faster.backend.repository;

import com.faster.backend.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface UserRepository extends JpaRepository<User, Long> {

    // ─── Find a user by their : ──────────
    // Used during login to check if the phone exists
    Optional<User> findByPhone(String phone);

    // ─── Check if a phone number is already taken ───
    boolean existsByPhone(String phone);

    // Check if email is already taken during registration
    boolean existsByEmail(String email);

    // Find user by email (for future email login option)
    Optional<User> findByEmail(String email);
}