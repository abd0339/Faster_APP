package com.faster.backend.repository;

import com.faster.backend.entity.DeviceToken;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface DeviceTokenRepository extends JpaRepository<DeviceToken, Long> {

    // All of a user's devices — pushes go to every one
    List<DeviceToken> findByUserId(Long userId);

    // Used for upsert-by-token (same physical device
    // re-registering shouldn't create a duplicate row)
    Optional<DeviceToken> findByFcmToken(String fcmToken);

    // Cleanup when FCM reports a token is no longer valid
    // (uninstalled app, token rotated, etc.)
    void deleteByFcmToken(String fcmToken);

    void deleteByUserIdAndFcmToken(Long userId, String fcmToken);
}