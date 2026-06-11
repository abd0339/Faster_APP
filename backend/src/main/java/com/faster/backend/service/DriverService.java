package com.faster.backend.service;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class DriverService {

    private final UserRepository userRepository;
    private final LocationService locationService;

    // ─── Toggle driver online with GPS + mode ─────────
    @Transactional
    public User goOnline(Long driverId,
            double lat,
            double lng,
            String mode) {

        User driver = getDriver(driverId);

        // Check if driver is blocked (debt >= $20)
        if (Boolean.TRUE.equals(driver.getIsBlocked())) {
            throw new RuntimeException(
                    "Your account is paused due to unpaid " +
                            "commission. Please settle via " +
                            "OMT or WishMoney.");
        }
        // Check if driver is verified by admin
        if (driver.getVerificationStatus() != User.DriverVerificationStatus.APPROVED) {
            throw new RuntimeException(
                    "Your account is pending verification. " +
                            "Please complete your profile and wait " +
                            "for admin approval.");
        }

        // Validate mode
        User.DriverMode driverMode;
        try {
            driverMode = User.DriverMode
                    .valueOf(mode.toUpperCase());
        } catch (IllegalArgumentException e) {
            throw new RuntimeException(
                    "Invalid mode. Use: PEOPLE, " +
                            "PACKAGE, or HYBRID");
        }

        // Update DB
        driver.setIsOnline(true);
        driver.setDriverMode(driverMode);
        userRepository.save(driver);

        // Store GPS in Redis
        locationService.driverOnline(
                driverId, lat, lng, mode);

        return driver;
    }

    // ─── Driver goes offline ──────────────────────────
    @Transactional
    public User goOffline(Long driverId) {
        User driver = getDriver(driverId);

        driver.setIsOnline(false);
        userRepository.save(driver);

        // Remove from Redis GeoSets
        locationService.driverOffline(driverId);

        return driver;
    }

    // ─── Switch mode while online ─────────────────────
    @Transactional
    public User switchMode(Long driverId,
            String newMode,
            double lat,
            double lng) {

        User driver = getDriver(driverId);

        if (!driver.getIsOnline()) {
            throw new RuntimeException(
                    "You must be online to switch mode");
        }

        User.DriverMode driverMode;
        try {
            driverMode = User.DriverMode
                    .valueOf(newMode.toUpperCase());
        } catch (IllegalArgumentException e) {
            throw new RuntimeException(
                    "Invalid mode. Use: PEOPLE, " +
                            "PACKAGE, or HYBRID");
        }

        // Remove from old GeoSets
        locationService.driverOffline(driverId);

        // Re-add to new GeoSets
        locationService.driverOnline(
                driverId, lat, lng, newMode);

        // Update DB
        driver.setDriverMode(driverMode);
        userRepository.save(driver);

        return driver;
    }

    // ─── Helper ───────────────────────────────────────
    private User getDriver(Long driverId) {
        User driver = userRepository
                .findById(driverId)
                .orElseThrow(() -> new RuntimeException("Driver not found"));

        if (driver.getRole() != User.Role.DRIVER) {
            throw new RuntimeException(
                    "User is not a driver");
        }

        return driver;
    }
}