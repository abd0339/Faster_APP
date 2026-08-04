package com.faster.backend.service;

import com.faster.backend.entity.DeviceToken;
import com.faster.backend.repository.DeviceTokenRepository;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;
import com.google.firebase.messaging.Notification;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;

/**
 * PushNotificationService — Phase 4 (FCM).
 *
 * Purely ADDITIVE: sends a push to every device a user is
 * logged into, ALONGSIDE the existing WebSocket broadcasts
 * and Twilio messages already fired at each order lifecycle
 * event — never replacing them. If Firebase Admin SDK was
 * never initialized (missing service account, same guard as
 * FirebaseConfig — see that class), or a specific device's
 * token is invalid, this is logged and swallowed. A push
 * failure can NEVER block an order from updating or a
 * notification from being sent through the other channels.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PushNotificationService {

    private final DeviceTokenRepository deviceTokenRepository;

    /**
     * Sends a push to every device the given user is
     * registered on. [data] is optional extra payload the
     * Flutter app can use to route a tap on the notification
     * (e.g. {"type": "order_status", "orderId": "123"}).
     */
    public void sendToUser(Long userId, String title, String body,
            Map<String, String> data) {

        List<DeviceToken> devices = deviceTokenRepository.findByUserId(userId);
        if (devices.isEmpty()) {
            // Perfectly normal — user has no registered device
            // (never opened the app on a version with FCM, or
            // never granted notification permission). Not an error.
            return;
        }

        for (DeviceToken device : devices) {
            sendToToken(device.getFcmToken(), title, body, data);
        }
    }

    /**
     * Sends to a single known FCM token directly — used when
     * the caller already has the token and doesn't need a
     * user lookup (rare; sendToUser above is the normal path).
     */
    public void sendToToken(String token, String title, String body,
            Map<String, String> data) {

        try {
            Message.Builder messageBuilder = Message.builder()
                    .setToken(token)
                    .setNotification(Notification.builder()
                            .setTitle(title)
                            .setBody(body)
                            .build());

            if (data != null) {
                messageBuilder.putAllData(data);
            }

            String response = FirebaseMessaging.getInstance()
                    .send(messageBuilder.build());

            log.info("✅ Push sent | token={}... | messageId={}",
                    token.substring(0, Math.min(12, token.length())), response);

        } catch (FirebaseMessagingException e) {
            if (e.getMessagingErrorCode() == MessagingErrorCode.UNREGISTERED
                    || e.getMessagingErrorCode() == MessagingErrorCode.INVALID_ARGUMENT) {
                // Token is dead (app uninstalled, token rotated,
                // malformed) — clean it up so we stop trying
                deviceTokenRepository.deleteByFcmToken(token);
                log.info("🗑️ Removed dead device token after push failure");
            } else {
                log.error("❌ Push failed | error={}", e.getMessage());
            }
        } catch (IllegalStateException e) {
            // FirebaseApp never initialized — same config issue
            // FirebaseConfig already warns about at startup.
            // Never let this bubble up and break the caller.
            log.warn("Push not sent — Firebase not initialized: {}",
                    e.getMessage());
        } catch (Exception e) {
            log.error("❌ Unexpected push failure | error={}", e.getMessage());
        }
    }

    /**
     * Registers or updates a device's FCM token for a user.
     * Upserts by token — if this exact token already exists
     * (same device re-registering), just updates which user
     * it belongs to instead of creating a duplicate row.
     */
    public void registerDevice(Long userId, String fcmToken, String platform) {
        DeviceToken device = deviceTokenRepository.findByFcmToken(fcmToken)
                .orElse(DeviceToken.builder()
                        .fcmToken(fcmToken)
                        .build());

        device.setUserId(userId);
        device.setPlatform(platform != null ? platform.toUpperCase() : "UNKNOWN");
        deviceTokenRepository.save(device);
    }

    /**
     * Unregisters a device — called on logout, so a signed-out
     * device stops receiving pushes meant for that user.
     *
     * FIX: derived delete queries (deleteByX) require an active
     * transaction to execute — without @Transactional here,
     * Spring throws "No EntityManager with actual transaction
     * available for current thread" the moment this runs.
     */
    @Transactional
    public void unregisterDevice(Long userId, String fcmToken) {
        deviceTokenRepository.deleteByUserIdAndFcmToken(userId, fcmToken);
    }
}