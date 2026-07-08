package com.faster.backend.service;

import com.faster.backend.dto.AuthResponse;
import com.faster.backend.dto.LoginRequest;
import com.faster.backend.dto.RegisterRequest;
import com.faster.backend.entity.OtpVerification;
import com.faster.backend.entity.User;
import com.faster.backend.repository.OtpVerificationRepository;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.security.JwtUtil;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.LocalDateTime;

@Slf4j
@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;
    private final OtpVerificationRepository otpRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtUtil jwtUtil;
    private final CommunicationService communicationService;

    // ─── OTP config ───────────────────────────────────
    private static final int OTP_EXPIRY_MINUTES = 10;
    private static final int OTP_MAX_ATTEMPTS = 3;
    private static final SecureRandom RANDOM = new SecureRandom();

    // ─────────────────────────────────────────────────
    // REGISTER
    // 1. Validate uniqueness
    // 2. Save user (isPhoneVerified = false)
    // 3. Generate + send OTP via SMS/WhatsApp
    // 4. Return response WITHOUT a token
    // (token is issued only after OTP verified)
    // ─────────────────────────────────────────────────
    @Transactional
    public AuthResponse register(RegisterRequest request) {

        // ─── Uniqueness checks ────────────────────────
        if (userRepository.existsByPhone(request.getPhone())) {
            throw new RuntimeException(
                    "Phone number is already registered");
        }
        if (userRepository.existsByEmail(request.getEmail())) {
            throw new RuntimeException(
                    "Email address is already registered");
        }

        // ─── Build and save user ──────────────────────
        User user = User.builder()
                .fullName(request.getFullName())
                .phone(request.getPhone())
                .email(request.getEmail().toLowerCase())
                .password(passwordEncoder.encode(request.getPassword()))
                .role(User.Role.valueOf(request.getRole().toUpperCase()))
                // Phone NOT verified yet — must complete OTP
                .isPhoneVerified(false)
                .isEmailVerified(false)
                .build();

        userRepository.save(user);

        // ─── Send OTP ─────────────────────────────────
        sendOtp(user);

        // ─── Return without token ─────────────────────
        // Token will be issued in verifyOtp()
        return AuthResponse.builder()
                .role(user.getRole().name())
                .fullName(user.getFullName())
                .email(user.getEmail())
                .phone(user.getPhone())
                .isBlocked(false)
                .isPhoneVerified(false)
                .requiresOtp(true)
                .message("Account created! We sent a 6-digit code to "
                        + maskPhone(user.getPhone())
                        + ". Enter it to activate your account.")
                .build();
    }

    // ─────────────────────────────────────────────────
    // VERIFY OTP
    // Called after register or when user enters the code.
    // On success: marks phone verified + issues JWT.
    // ─────────────────────────────────────────────────
    @Transactional
    public AuthResponse verifyOtp(String phone, String code) {

        // ─── Find user by phone ───────────────────────
        User user = userRepository.findByPhone(phone)
                .orElseThrow(() -> new RuntimeException(
                        "No account found with this phone number"));

        if (Boolean.TRUE.equals(user.getIsPhoneVerified())) {
            throw new RuntimeException(
                    "Phone number is already verified");
        }

        // ─── Find latest OTP ──────────────────────────
        OtpVerification otp = otpRepository
                .findTopByUserIdAndIsUsedFalseOrderByCreatedAtDesc(
                        user.getId())
                .orElseThrow(() -> new RuntimeException(
                        "No active OTP found. Request a new code."));

        // ─── Check expiry ─────────────────────────────
        if (LocalDateTime.now().isAfter(otp.getExpiresAt())) {
            otpRepository.deleteAllByUserId(user.getId());
            throw new RuntimeException(
                    "Code has expired. Request a new one.");
        }

        // ─── Check attempt limit ──────────────────────
        if (otp.getAttempts() >= OTP_MAX_ATTEMPTS) {
            otpRepository.deleteAllByUserId(user.getId());
            throw new RuntimeException(
                    "Too many wrong attempts. Request a new code.");
        }

        // ─── Check code ───────────────────────────────
        if (!otp.getCode().equals(code.trim())) {
            // Increment attempts
            otp.setAttempts(otp.getAttempts() + 1);
            otpRepository.save(otp);

            int remaining = OTP_MAX_ATTEMPTS - otp.getAttempts();
            throw new RuntimeException(
                    "Wrong code. " + remaining + " attempt(s) remaining.");
        }

        // ─── SUCCESS ──────────────────────────────────
        // Mark OTP used + mark phone verified
        otp.setIsUsed(true);
        otpRepository.save(otp);

        user.setIsPhoneVerified(true);
        userRepository.save(user);

        // Clean up all OTPs for this user
        otpRepository.deleteAllByUserId(user.getId());

        log.info("✅ Phone verified for user {} ({})",
                user.getFullName(), phone);

        // Issue JWT — first time user gets a token
        String token = jwtUtil.generateToken(
                user.getEmail(), user.getRole().name());

        return AuthResponse.builder()
                .token(token)
                .role(user.getRole().name())
                .fullName(user.getFullName())
                .email(user.getEmail())
                .phone(user.getPhone())
                .isBlocked(user.getIsBlocked())
                .isPhoneVerified(true)
                .requiresOtp(false)
                .message("Phone verified! Welcome to Faster, "
                        + user.getFullName() + "!")
                .build();
    }

    // ─────────────────────────────────────────────────
    // RESEND OTP
    // User can request a new code if it expired or
    // they didn't receive it. Old OTPs are deleted.
    // ─────────────────────────────────────────────────
    @Transactional
    public AuthResponse resendOtp(String phone) {

        User user = userRepository.findByPhone(phone)
                .orElseThrow(() -> new RuntimeException(
                        "No account found with this phone number"));

        if (Boolean.TRUE.equals(user.getIsPhoneVerified())) {
            throw new RuntimeException(
                    "Phone number is already verified");
        }

        // Delete existing OTPs and send fresh one
        otpRepository.deleteAllByUserId(user.getId());
        sendOtp(user);

        return AuthResponse.builder()
                .role(user.getRole().name())
                .fullName(user.getFullName())
                .email(user.getEmail())
                .phone(user.getPhone())
                .isPhoneVerified(false)
                .requiresOtp(true)
                .message("New code sent to "
                        + maskPhone(phone) + ".")
                .build();
    }

    // ─────────────────────────────────────────────────
    // LOGIN
    // Blocks login if phone not verified yet.
    // ─────────────────────────────────────────────────
    @Transactional
    public AuthResponse login(LoginRequest request) {

        if (request.getEmail() == null &&
                request.getPhone() == null) {
            throw new RuntimeException(
                    "Please provide your email or phone number");
        }

        // ─── Find user ────────────────────────────────
        User user;
        if (request.getEmail() != null &&
                !request.getEmail().isBlank()) {
            user = userRepository
                    .findByEmail(request.getEmail().toLowerCase())
                    .orElseThrow(() -> new RuntimeException(
                            "No account found with this email address"));
        } else {
            user = userRepository
                    .findByPhone(request.getPhone())
                    .orElseThrow(() -> new RuntimeException(
                            "No account found with this phone number"));
        }

        // ─── Password check ───────────────────────────
        if (!passwordEncoder.matches(
                request.getPassword(), user.getPassword())) {
            throw new RuntimeException(
                    "Incorrect password. Please try again");
        }

        // ─── Account checks ───────────────────────────
        if (Boolean.FALSE.equals(user.getIsActive())) {
            throw new RuntimeException(
                    "This account has been deactivated. Contact support");
        }

        if (Boolean.TRUE.equals(user.getIsBlocked())) {
            throw new RuntimeException(
                    "Your account has been paused by admin. "
                            + "Please settle your outstanding commission "
                            + "via OMT or WishMoney, then contact admin.");
        }

        // ─── Phone verification gate ──────────────────
        // If phone not verified, send a fresh OTP and
        // block login — user must verify first.
        if (Boolean.FALSE.equals(user.getIsPhoneVerified())) {
            otpRepository.deleteAllByUserId(user.getId());
            sendOtp(user);
            return AuthResponse.builder()
                    .role(user.getRole().name())
                    .fullName(user.getFullName())
                    .email(user.getEmail())
                    .phone(user.getPhone())
                    .isPhoneVerified(false)
                    .requiresOtp(true)
                    .message("Please verify your phone number. "
                            + "We sent a new code to "
                            + maskPhone(user.getPhone()) + ".")
                    .build();
        }

        // ─── Issue JWT ────────────────────────────────
        String token = jwtUtil.generateToken(
                user.getEmail(), user.getRole().name());

        return AuthResponse.builder()
                .token(token)
                .role(user.getRole().name())
                .fullName(user.getFullName())
                .email(user.getEmail())
                .phone(user.getPhone())
                .isBlocked(user.getIsBlocked())
                .isPhoneVerified(true)
                .requiresOtp(false)
                .message("Welcome back, " + user.getFullName() + "!")
                .build();
    }

    // ─────────────────────────────────────────────────
    // PRIVATE HELPERS
    // ─────────────────────────────────────────────────

    // Generate OTP, save to DB, send via CommunicationService
    private void sendOtp(User user) {
        // Generate secure 6-digit code
        String code = String.format("%06d",
                RANDOM.nextInt(900000) + 100000);

        // Save to DB
        OtpVerification otp = OtpVerification.builder()
                .userId(user.getId())
                .phone(user.getPhone())
                .code(code)
                .expiresAt(LocalDateTime.now()
                        .plusMinutes(OTP_EXPIRY_MINUTES))
                .attempts(0)
                .isUsed(false)
                .build();

        otpRepository.save(otp);

        // Build the OTP message
        String message = "🔐 *Faster App — Phone Verification*\n\n"
                + "Hello " + user.getFullName() + ",\n\n"
                + "Your verification code is:\n\n"
                + "*" + code + "*\n\n"
                + "This code expires in " + OTP_EXPIRY_MINUTES
                + " minutes.\n\n"
                + "If you did not request this, ignore this message.";

        // Send via CommunicationService (Twilio/Vonage)
        // Pass null for orderId/trackingCode — not order-related
        communicationService.sendOtpMessage(user.getPhone(), message);

        log.info("📲 OTP sent to {} for user {}",
                maskPhone(user.getPhone()), user.getFullName());
    }

    // Mask phone for logging: +96170123456 → +961***3456
    private String maskPhone(String phone) {
        if (phone == null || phone.length() < 6)
            return "***";
        return phone.substring(0, 4)
                + "***"
                + phone.substring(phone.length() - 4);
    }
}