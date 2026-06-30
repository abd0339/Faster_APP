package com.faster.backend.service;

import com.faster.backend.entity.MessageLog;
import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.repository.MessageLogRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.nio.charset.StandardCharsets;
import java.time.format.DateTimeFormatter;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

// ─────────────────────────────────────────────────────
// CommunicationService
//
// Handles ALL outgoing SMS and WhatsApp messages.
// Toggle between providers by setting SMS_PROVIDER
// in your .env file:
//
//   SMS_PROVIDER=twilio   → uses Twilio REST API
//   SMS_PROVIDER=vonage   → uses Vonage Messages API
//
// Every message is logged to the message_logs table
// for audit and support purposes.
//
// Uses Spring's RestTemplate (no external SDK needed).
// This avoids adding heavy dependencies to pom.xml.
// ─────────────────────────────────────────────────────
@Slf4j
@Service
@RequiredArgsConstructor
public class CommunicationService {

    private final MessageLogRepository messageLogRepository;
    private final RestTemplate restTemplate;

    // ─── Provider toggle ──────────────────────────────
    // Set SMS_PROVIDER=twilio or SMS_PROVIDER=vonage
    @Value("${sms.provider:twilio}")
    private String provider;

    // ─── Shared ───────────────────────────────────────
    // Your company sender name or phone number
    // e.g. "FasterAPP" or "+19876543210"
    @Value("${sms.sender.id:FasterAPP}")
    private String senderId;

    // ─── Backend public URL ───────────────────────────
    // Used to build tracking links in messages
    // e.g. https://your-domain.com
    @Value("${app.base.url:http://localhost:8080}")
    private String baseUrl;

    // ─── Twilio credentials ───────────────────────────
    @Value("${sms.twilio.account-sid:}")
    private String twilioAccountSid;

    @Value("${sms.twilio.auth-token:}")
    private String twilioAuthToken;

    // Twilio WhatsApp-enabled number (must be registered)
    // Format: whatsapp:+14155238886
    @Value("${sms.twilio.whatsapp-from:}")
    private String twilioWhatsAppFrom;

    // ─── Vonage credentials ───────────────────────────
    @Value("${sms.vonage.api-key:}")
    private String vonageApiKey;

    @Value("${sms.vonage.api-secret:}")
    private String vonageApiSecret;

    // ─────────────────────────────────────────────────
    // PUBLIC API — The 4 message types the system sends
    // ─────────────────────────────────────────────────

    // ── 1. O2O: Send tracking link to offline customer ─
    // Called by OrderService.createO2OOrder()
    // Sends full order details + tracking link
    public void sendO2OTrackingLink(Order order) {
        if (order.getOfflineCustomerPhone() == null) return;

        String trackingUrl = baseUrl
                + "/tracking/public/"
                + order.getTrackingCode();

        String message = buildO2OMessage(order, trackingUrl);

        sendMessage(
            order.getOfflineCustomerPhone(),
            message,
            MessageLog.MessageType.O2O_TRACKING_LINK,
            order.getId(),
            order.getTrackingCode()
        );
    }

    // ── 2. O2O: Notify customer when driver assigned ───
    // Called by OrderService.acceptOrder() for O2O orders
    public void sendDriverAssignedNotification(Order order) {
        if (order.getOfflineCustomerPhone() == null) return;
        if (order.getDriver() == null) return;

        String trackingUrl = baseUrl
                + "/tracking/public/"
                + order.getTrackingCode();

        String driverName = order.getDriver().getFullName();
        String vehicleType = order.getDriver().getVehicleType() != null
                ? order.getDriver().getVehicleType()
                : "vehicle";
        String plate = order.getDriver().getVehiclePlate() != null
                ? order.getDriver().getVehiclePlate()
                : "N/A";

        String message = "🚗 *Faster App — Driver On The Way!*\n\n"
                + "Your driver *" + driverName + "* is heading to you.\n"
                + "🚘 Vehicle: " + vehicleType + " | Plate: " + plate + "\n\n"
                + "📍 Track your order live:\n"
                + trackingUrl + "\n\n"
                + "Order: " + order.getTrackingCode() + "\n"
                + "Pay *$" + order.getGrandTotal() + "* cash on arrival.";

        sendMessage(
            order.getOfflineCustomerPhone(),
            message,
            MessageLog.MessageType.O2O_DRIVER_ASSIGNED,
            order.getId(),
            order.getTrackingCode()
        );
    }

    // ── 3. Admin manually notifies driver of debt ─────
    // Called from AdminController when admin clicks
    // "Notify Driver" button on the debt management page
    public void sendDriverDebtNotification(
            User driver, String amountDue) {

        if (driver.getPhone() == null) return;

        String message = "💰 *Faster App — Commission Due*\n\n"
                + "Hello " + driver.getFullName() + ",\n\n"
                + "Your outstanding commission balance is: "
                + "*$" + amountDue + "*\n\n"
                + "Please settle via:\n"
                + "• OMT\n"
                + "• WishMoney\n\n"
                + "After paying, send your receipt to the "
                + "admin on WhatsApp to reactivate your account.\n\n"
                + "Thank you for being a Faster driver! 🚀";

        sendMessage(
            driver.getPhone(),
            message,
            MessageLog.MessageType.DRIVER_DEBT_NOTIFICATION,
            null,
            null
        );
    }

    // ── 4. Platform announcement to a list of phones ──
    // Called when admin broadcasts a message to drivers
    // or all active users
    public void sendPlatformAnnouncement(
            String phone, String announcementText) {

        if (phone == null || phone.isBlank()) return;

        String message = "📢 *Faster App — Announcement*\n\n"
                + announcementText + "\n\n"
                + "— The Faster Team";

        sendMessage(
            phone,
            message,
            MessageLog.MessageType.PLATFORM_ANNOUNCEMENT,
            null,
            null
        );
    }

    // ── 5. Send OTP for phone verification ───────────
    // Called by AuthService during register/login
    // when user needs to verify their phone number
    public void sendOtpMessage(String phone, String messageBody) {
        if (phone == null || phone.isBlank()) return;
        sendMessage(
            phone,
            messageBody,
            MessageLog.MessageType.OTP_VERIFICATION,
            null,
            null
        );
    }

    // ─────────────────────────────────────────────────
    // CORE SEND — Routes to the correct provider
    // ─────────────────────────────────────────────────
    private void sendMessage(
            String toPhone,
            String body,
            MessageLog.MessageType type,
            Long orderId,
            String trackingCode) {

        // Create audit log entry BEFORE sending
        // Named 'msgLog' to avoid shadowing @Slf4j 'log' field
        MessageLog msgLog = MessageLog.builder()
                .recipientPhone(toPhone)
                .messageType(type)
                .provider(provider)
                .messageBody(body)
                .status(MessageLog.DeliveryStatus.PENDING)
                .relatedOrderId(orderId)
                .trackingCode(trackingCode)
                .build();

        msgLog = messageLogRepository.save(msgLog);

        try {
            String providerMessageId;

            // Route to correct provider
            if ("vonage".equalsIgnoreCase(provider)) {
                providerMessageId = sendViaVonage(toPhone, body);
            } else {
                // Default: Twilio
                providerMessageId = sendViaTwilio(toPhone, body);
            }

            // Update msgLog — success
            msgLog.setStatus(MessageLog.DeliveryStatus.SENT);
            msgLog.setProviderMessageId(providerMessageId);
            messageLogRepository.save(msgLog);

            log.info("✅ Message sent via {} to {} | type={} | id={}",
                provider, toPhone, type, providerMessageId);

        } catch (Exception e) {
            // Update log — failure
            msgLog.setStatus(MessageLog.DeliveryStatus.FAILED);
            msgLog.setErrorMessage(e.getMessage());
            messageLogRepository.save(msgLog);

            // Log the error but DON'T crash the calling service
            // A failed SMS should never block an order from being created
            log.error("❌ Message failed via {} to {} | type={} | error={}",
                provider, toPhone, type, e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────
    // TWILIO — Sends via WhatsApp Business API
    // ─────────────────────────────────────────────────
    // Twilio endpoint:
    //   POST https://api.twilio.com/2010-04-01/Accounts/{SID}/Messages.json
    //
    // Auth: HTTP Basic with AccountSID:AuthToken
    // Body: form-encoded (not JSON)
    //
    // For WhatsApp: both From and To must be prefixed
    // with "whatsapp:" — e.g. whatsapp:+96170000001
    // ─────────────────────────────────────────────────
    private String sendViaTwilio(String toPhone, String body) {
        String url = "https://api.twilio.com/2010-04-01/Accounts/"
                + twilioAccountSid
                + "/Messages.json";

        // Twilio uses HTTP Basic Auth
        String credentials = twilioAccountSid + ":" + twilioAuthToken;
        String encodedAuth = Base64.getEncoder()
                .encodeToString(credentials.getBytes(StandardCharsets.UTF_8));

        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Basic " + encodedAuth);
        // Twilio requires form-encoded body, NOT JSON
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);

        // Normalize phone: ensure it starts with +
        String normalizedTo = normalizePhone(toPhone);

        // WhatsApp messages need the "whatsapp:" prefix
        String formBody = "From=" + encode(twilioWhatsAppFrom)
                + "&To=" + encode("whatsapp:" + normalizedTo)
                + "&Body=" + encode(body);

        HttpEntity<String> entity = new HttpEntity<>(formBody, headers);

        ResponseEntity<Map> response = restTemplate.exchange(
                url,
                HttpMethod.POST,
                entity,
                Map.class
        );

        // Twilio returns the SID in the "sid" field
        // e.g. "SMxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        Map<?, ?> responseBody = response.getBody();
        if (responseBody == null || responseBody.get("sid") == null) {
            throw new RuntimeException(
                "Twilio returned empty response: " + response.getStatusCode());
        }

        return responseBody.get("sid").toString();
    }

    // ─────────────────────────────────────────────────
    // VONAGE — Sends via SMS API
    // ─────────────────────────────────────────────────
    // Vonage endpoint:
    //   POST https://rest.nexmo.com/sms/json
    //
    // Auth: api_key and api_secret in the JSON body
    // Body: JSON
    //
    // Note: Vonage does not have native WhatsApp
    // on the basic SMS API. For WhatsApp via Vonage,
    // you need their Messages API (separate setup).
    // This implementation uses SMS which works globally.
    // ─────────────────────────────────────────────────
    private String sendViaVonage(String toPhone, String body) {
        String url = "https://rest.nexmo.com/sms/json";

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        String normalizedTo = normalizePhone(toPhone)
                .replace("+", ""); // Vonage needs no + prefix

        Map<String, String> requestBody = new HashMap<>();
        requestBody.put("api_key", vonageApiKey);
        requestBody.put("api_secret", vonageApiSecret);
        requestBody.put("to", normalizedTo);
        requestBody.put("from", senderId);
        requestBody.put("text", body);

        HttpEntity<Map<String, String>> entity =
                new HttpEntity<>(requestBody, headers);

        ResponseEntity<Map> response = restTemplate.exchange(
                url,
                HttpMethod.POST,
                entity,
                Map.class
        );

        // Vonage response structure:
        // { "messages": [{ "message-id": "...", "status": "0" }] }
        Map<?, ?> responseBody = response.getBody();
        if (responseBody == null) {
            throw new RuntimeException("Vonage returned empty response");
        }

        @SuppressWarnings("unchecked")
        java.util.List<Map<?, ?>> messages =
                (java.util.List<Map<?, ?>>) responseBody.get("messages");

        if (messages == null || messages.isEmpty()) {
            throw new RuntimeException(
                "Vonage returned no messages in response");
        }

        Map<?, ?> first = messages.get(0);
        String status = String.valueOf(first.get("status"));

        // Vonage status "0" = success
        if (!"0".equals(status)) {
            String error = first.getOrDefault(
                "error-text", "Unknown error").toString();
            throw new RuntimeException(
                "Vonage error: " + error + " (status=" + status + ")");
        }

        return String.valueOf(first.get("message-id"));
    }

    // ─────────────────────────────────────────────────
    // MESSAGE BUILDER — O2O full message
    // "Full message: greeting + order details +
    //  tracking link + driver info when assigned"
    // ─────────────────────────────────────────────────
    private String buildO2OMessage(Order order, String trackingUrl) {
        String merchantName = order.getMerchant() != null
                ? order.getMerchant().getFullName()
                : "Store";

        String area = order.getDeliveryAddress() != null
                ? order.getDeliveryAddress()
                : order.getOfflineCustomerLandmark() != null
                    ? order.getOfflineCustomerLandmark()
                    : "Your location";

        String createdTime = order.getCreatedAt() != null
                ? order.getCreatedAt().format(
                    DateTimeFormatter.ofPattern("hh:mm a"))
                : "just now";

        return "👋 *Welcome to Faster App!*\n\n"
                + "Your order from *" + merchantName
                + "* has been placed at " + createdTime + ".\n\n"
                + "─────────────────\n"
                + "📦 *Order Details*\n"
                + "─────────────────\n"
                + "🔖 Order: *" + order.getTrackingCode() + "*\n"
                + "📍 Delivery to: " + area + "\n"
                + "💰 Total to pay: *$" + order.getGrandTotal() + "* cash\n\n"
                + "📲 *Track your order live:*\n"
                + trackingUrl + "\n\n"
                + "We are finding the nearest driver for you. "
                + "You will receive another message when your "
                + "driver is on the way. 🚗\n\n"
                + "— Faster Team";
    }

    // ─────────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────────

    // Ensure phone starts with + for international format
    // e.g. "96170000001" → "+96170000001"
    //      "+96170000001" → "+96170000001" (unchanged)
    private String normalizePhone(String phone) {
        if (phone == null) return "";
        phone = phone.trim().replaceAll("\\s+", "");
        if (!phone.startsWith("+")) {
            return "+" + phone;
        }
        return phone;
    }

    // URL-encode a string for Twilio form body
    private String encode(String value) {
        try {
            return java.net.URLEncoder.encode(
                value, StandardCharsets.UTF_8.name());
        } catch (Exception e) {
            return value;
        }
    }
}