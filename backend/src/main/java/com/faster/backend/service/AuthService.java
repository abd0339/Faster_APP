package com.faster.backend.service;

import com.faster.backend.dto.AuthResponse;
import com.faster.backend.dto.LoginRequest;
import com.faster.backend.dto.RegisterRequest;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.security.JwtUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtUtil jwtUtil;

    // ─── REGISTER ────────────────────────────────────
    public AuthResponse register(RegisterRequest request) {

        // Check phone is not already used
        if (userRepository.existsByPhone(request.getPhone())) {
            throw new RuntimeException("Phone number is already registered");
        }

        // Check email is not already used
        if (userRepository.existsByEmail(request.getEmail())) {
            throw new RuntimeException("Email address is already registered");
        }

        // Build and save the new user
        User user = User.builder()
                .fullName(request.getFullName())
                .phone(request.getPhone())
                .email(request.getEmail().toLowerCase())
                .password(passwordEncoder.encode(request.getPassword()))
                .role(User.Role.valueOf(request.getRole().toUpperCase()))
                .build();

        userRepository.save(user);

        // Generate JWT token
        String token = jwtUtil.generateToken(
                user.getEmail(),
                user.getRole().name()
        );

        return AuthResponse.builder()
                .token(token)
                .role(user.getRole().name())
                .fullName(user.getFullName())
                .email(user.getEmail())
                .phone(user.getPhone())
                .isBlocked(user.getIsBlocked())
                .isEmailVerified(user.getIsEmailVerified())
                .message("Registration successful. Welcome to Faster!")
                .build();
    }

    // ─── LOGIN ────────────────────────────────────────
    public AuthResponse login(LoginRequest request) {

        // Must provide email or phone
        if (request.getEmail() == null && request.getPhone() == null) {
            throw new RuntimeException("Please provide your email or phone number");
        }

        // Find the user by email or phone
        User user;

        if (request.getEmail() != null && !request.getEmail().isBlank()) {
            // Login with email
            user = userRepository.findByEmail(request.getEmail().toLowerCase())
                    .orElseThrow(() ->
                        new RuntimeException("No account found with this email address"));
        } else {
            // Login with phone
            user = userRepository.findByPhone(request.getPhone())
                    .orElseThrow(() ->
                        new RuntimeException("No account found with this phone number"));
        }

        // Check password is correct
        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new RuntimeException("Incorrect password. Please try again");
        }

        // Check if account is active
        if (Boolean.FALSE.equals(user.getIsActive())) {
            throw new RuntimeException("This account has been deactivated. Contact support");
        }

        // Check if driver is blocked due to debt
        if (Boolean.TRUE.equals(user.getIsBlocked())) {
            throw new RuntimeException(
                "Your account is paused. You have reached the $20 debt limit. " +
                "Please settle your balance via OMT or WishMoney to continue"
            );
        }

        // Generate JWT token
        String token = jwtUtil.generateToken(
                user.getEmail(),
                user.getRole().name()
        );

        return AuthResponse.builder()
                .token(token)
                .role(user.getRole().name())
                .fullName(user.getFullName())
                .email(user.getEmail())
                .phone(user.getPhone())
                .isBlocked(user.getIsBlocked())
                .isEmailVerified(user.getIsEmailVerified())
                .message("Welcome back, " + user.getFullName() + "!")
                .build();
    }
}