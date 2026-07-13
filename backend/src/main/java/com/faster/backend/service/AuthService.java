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
    // ─────────────────────────────────────────────────
    @Transactional
    public AuthResponse register(RegisterRequest request) {

        if (userRepository.existsByPhone(request.getPhone())) {
            throw new RuntimeException("Phone number is already registered");
        }
        if (userRepository.existsByEmail(request.getEmail())) {
            throw new RuntimeException("Email address is already registered");
        }

        User user = User.builder()
                .fullName(request.getFullName())
                .phone(request.getPhone())
                .email(request.getEmail().toLowerCase())
                .password(passwordEncoder.encode(request.getPassword()))
                .role(User.Role.valueOf(request.getRole().toUpperCase()))
                .isPhoneVerified(false)
                .isEmailVerified(false)
                .build();

        userRepository.save(user);

        // Default channel on first registration — WhatsApp
        sendOtp(user, CommunicationService.Channel.WHATSAPP);

        return AuthResponse.builder()
                .role(user.getRole().name())
                .fullName(user.getFullName())
                .email(user.getEmail())
                .phone(user.getPhone())
                .isBlocked(false)
                .isPhoneVerified(false)
                .requiresOtp(true)
                .message("Account created! We sent a 6-digit code via WhatsApp to "
                        + maskPhone(user.getPhone())
                        + ". Enter it to activate your account.")
                .build();
    }

    // ─────────────────────────────────────────────────
    // VERIFY OTP — unchanged
    // ─────────────────────────────────────────────────
    @Transactional
    public AuthResponse verifyOtp(String phone, String code) {

        User user = userRepository.findByPhone(phone)
                .orElseThrow(() -> new RuntimeException(
                        "No account found with this phone number"));

        if (Boolean.TRUE.equals(user.getIsPhoneVerified())) {
            throw new RuntimeException("Phone number is already verified");
        }

        OtpVerification otp = otpRepository
                .findTopByUserIdAndIsUsedFalseOrderByCreatedAtDesc(user.getId())
                .orElseThrow(() -> new RuntimeException(
                        "No active OTP found. Request a new code."));

        if (LocalDateTime.now().isAfter(otp.getExpiresAt())) {
            otpRepository.deleteAllByUserId(user.getId());
            throw new RuntimeException("Code has expired. Request a new one.");
        }

        if (otp.getAttempts() >= OTP_MAX_ATTEMPTS) {
            otpRepository.deleteAllByUserId(user.getId());
            throw new RuntimeException(
                    "Too many wrong attempts. Request a new code.");
        }

        if (!otp.getCode().equals(code.trim())) {
            otp.setAttempts(otp.getAttempts() + 1);
            otpRepository.save(otp);
            int remaining = OTP_MAX_ATTEMPTS - otp.getAttempts();
            throw new RuntimeException(
                    "Wrong code. " + remaining + " attempt(s) remaining.");
        }

        otp.setIsUsed(true);
        otpRepository.save(otp);

        user.setIsPhoneVerified(true);
        userRepository.save(user);

        otpRepository.deleteAllByUserId(user.getId());

        log.info("✅ Phone verified for user {} ({})", user.getFullName(), phone);

        String token = jwtUtil.generateToken(user.getEmail(), user.getRole().name());

        return AuthResponse.builder()
                .token(token)
                .role(user.getRole().name())
                .fullName(user.getFullName())
                .email(user.getEmail())
                .phone(user.getPhone())
                .isBlocked(user.getIsBlocked())
                .isPhoneVerified(true)
                .requiresOtp(false)
                .message("Phone verified! Welcome to Faster, " + user.getFullName() + "!")
                .build();
    }

    // ─────────────────────────────────────────────────
    // RESEND OTP
    // FIX: now accepts an explicit channel so the Flutter
    // app can offer "Resend via WhatsApp" (default) or
    // "Resend via SMS instead" if the customer says they
    // never received the WhatsApp message. Pass null to
    // keep the previous default (WhatsApp) behavior.
    // ─────────────────────────────────────────────────
    @Transactional
    public AuthResponse resendOtp(String phone, String channel) {

        User user = userRepository.findByPhone(phone)
                .orElseThrow(() -> new RuntimeException(
                        "No account found with this phone number"));

        if (Boolean.TRUE.equals(user.getIsPhoneVerified())) {
            throw new RuntimeException("Phone number is already verified");
        }

        CommunicationService.Channel resolvedChannel = resolveChannel(channel);

        otpRepository.deleteAllByUserId(user.getId());
        sendOtp(user, resolvedChannel);

        String channelLabel = resolvedChannel == CommunicationService.Channel.SMS
                ? "SMS" : "WhatsApp";

        return AuthResponse.builder()
                .role(user.getRole().name())
                .fullName(user.getFullName())
                .email(user.getEmail())
                .phone(user.getPhone())
                .isPhoneVerified(false)
                .requiresOtp(true)
                .message("New code sent via " + channelLabel + " to "
                        + maskPhone(phone) + ".")
                .build();
    }

    // ─────────────────────────────────────────────────
    // LOGIN — unchanged except sendOtp() now takes a channel
    // ─────────────────────────────────────────────────
    @Transactional
    public AuthResponse login(LoginRequest request) {

        if (request.getEmail() == null && request.getPhone() == null) {
            throw new RuntimeException("Please provide your email or phone number");
        }

        User user;
        if (request.getEmail() != null && !request.getEmail().isBlank()) {
            user = userRepository.findByEmail(request.getEmail().toLowerCase())
                    .orElseThrow(() -> new RuntimeException(
                            "No account found with this email address"));
        } else {
            user = userRepository.findByPhone(request.getPhone())
                    .orElseThrow(() -> new RuntimeException(
                            "No account found with this phone number"));
        }

        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new RuntimeException("Incorrect password. Please try again");
        }

        if (Boolean.FALSE.equals(user.getIsActive())) {
            throw new RuntimeException("This account has been deactivated. Contact support");
        }

        if (Boolean.TRUE.equals(user.getIsBlocked())) {
            throw new RuntimeException(
                    "Your account has been paused by admin. "
                            + "Please settle your outstanding commission "
                            + "via OMT or WishMoney, then contact admin.");
        }

        if (Boolean.FALSE.equals(user.getIsPhoneVerified())) {
            otpRepository.deleteAllByUserId(user.getId());
            sendOtp(user, CommunicationService.Channel.WHATSAPP);
            return AuthResponse.builder()
                    .role(user.getRole().name())
                    .fullName(user.getFullName())
                    .email(user.getEmail())
                    .phone(user.getPhone())
                    .isPhoneVerified(false)
                    .requiresOtp(true)
                    .message("Please verify your phone number. "
                            + "We sent a new code via WhatsApp to "
                            + maskPhone(user.getPhone()) + ".")
                    .build();
        }

        String token = jwtUtil.generateToken(user.getEmail(), user.getRole().name());

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

    private void sendOtp(User user, CommunicationService.Channel channel) {
        String code = String.format("%06d", RANDOM.nextInt(900000) + 100000);

        OtpVerification otp = OtpVerification.builder()
                .userId(user.getId())
                .phone(user.getPhone())
                .code(code)
                .expiresAt(LocalDateTime.now().plusMinutes(OTP_EXPIRY_MINUTES))
                .attempts(0)
                .isUsed(false)
                .build();

        otpRepository.save(otp);

        String message = "🔐 *Faster App — Phone Verification*\n\n"
                + "Hello " + user.getFullName() + ",\n\n"
                + "Your verification code is:\n\n"
                + "*" + code + "*\n\n"
                + "This code expires in " + OTP_EXPIRY_MINUTES + " minutes.\n\n"
                + "If you did not request this, ignore this message.";

        communicationService.sendOtpMessage(user.getPhone(), message, channel);

        log.info("📲 OTP sent via {} to {} for user {}",
                channel, maskPhone(user.getPhone()), user.getFullName());
    }

    // Accepts "SMS" / "WHATSAPP" (case-insensitive), defaults
    // to WhatsApp for null/blank/unrecognized values — never
    // throws, since a typo here should never block a resend.
    private CommunicationService.Channel resolveChannel(String channel) {
        if (channel == null || channel.isBlank()) {
            return CommunicationService.Channel.WHATSAPP;
        }
        try {
            return CommunicationService.Channel.valueOf(channel.trim().toUpperCase());
        } catch (IllegalArgumentException e) {
            return CommunicationService.Channel.WHATSAPP;
        }
    }

    private String maskPhone(String phone) {
        if (phone == null || phone.length() < 6) return "***";
        return phone.substring(0, 4) + "***" + phone.substring(phone.length() - 4);
    }
}