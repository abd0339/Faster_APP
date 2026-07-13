package com.faster.backend.service;

import com.faster.backend.entity.MessageLog;
import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.repository.MessageLogRepository;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

// ─────────────────────────────────────────────────────
// CommunicationService — Vonage ONLY.
//
// FIX: Twilio has been fully removed. This app now uses
// exclusively Vonage's Messages API (WhatsApp) and SMS API
// (Alphanumeric Sender ID), per product decision to
// consolidate on one provider.
//
// TWO CHANNELS, CALLER CHOOSES:
//   Channel.WHATSAPP (default/primary) — Vonage Messages
//     API v1, authenticated with a JWT signed by the
//     Application's private key (Application ID = "kid").
//   Channel.SMS (fallback/alternate) — Vonage's classic
//     SMS API, authenticated with api_key + api_secret,
//     sent from an Alphanumeric Sender ID (e.g. "FasterApp")
//     rather than a phone number — required for Lebanon,
//     where numeric sender IDs aren't reliably supported.
//
// Every message is logged to message_logs (channel + status)
// for audit and support purposes. A failed send NEVER
// throws back up to the caller — it's logged and swallowed,
// so a broken SMS/WhatsApp provider can never block an
// order or a registration from completing.
// ─────────────────────────────────────────────────────
@Slf4j
@Service
@RequiredArgsConstructor
public class CommunicationService {

    private final MessageLogRepository messageLogRepository;
    private final RestTemplate restTemplate;

    public enum Channel { WHATSAPP, SMS }

    // ─── Shared ───────────────────────────────────────
    @Value("${app.base.url:http://localhost:8080}")
    private String baseUrl;

    // Which channel to use when the caller doesn't specify
    // one explicitly (register/O2O/notifications all default
    // to WhatsApp per product decision — richer formatting,
    // free-ish delivery, no per-message carrier fee like SMS).
    @Value("${vonage.default-channel:WHATSAPP}")
    private String defaultChannelName;

    // ─── Vonage Messages API (WhatsApp) — JWT auth ────
    @Value("${vonage.application-id:}")
    private String vonageApplicationId;

    // Path to the PEM private key file, mounted into the
    // container as a read-only file — NEVER stored in git,
    // NEVER baked into the Docker image. See docker-compose.
    @Value("${vonage.private-key-path:}")
    private String vonagePrivateKeyPath;

    // WhatsApp sender — sandbox number for now
    // (whatsapp:+14157386102-style, digits only here),
    // switches to your approved WhatsApp Business number
    // once Meta approval clears — no code change needed,
    // just update this one env var.
    @Value("${vonage.whatsapp-from:}")
    private String vonageWhatsAppFrom;

    // ─── Vonage SMS API — api_key/api_secret auth ─────
    @Value("${vonage.api-key:}")
    private String vonageApiKey;

    @Value("${vonage.api-secret:}")
    private String vonageApiSecret;

    // Alphanumeric Sender ID — e.g. "FasterApp".
    // Lebanon requires this instead of a numeric sender;
    // see Faster_Logistics docs for why.
    @Value("${vonage.sms-sender:FasterApp}")
    private String vonageSmsSender;

    // ─────────────────────────────────────────────────
    // PUBLIC API — message types the system sends
    // ─────────────────────────────────────────────────

    // ── 1. O2O: Send tracking link to offline customer ─
    public void sendO2OTrackingLink(Order order) {
        if (order.getOfflineCustomerPhone() == null) return;

        String trackingUrl = baseUrl + "/tracking/public/" + order.getTrackingCode();
        String message = buildO2OMessage(order, trackingUrl);

        sendMessage(order.getOfflineCustomerPhone(), message,
                MessageLog.MessageType.O2O_TRACKING_LINK,
                order.getId(), order.getTrackingCode(), defaultChannel());
    }

    // ── 2. O2O: Notify customer when driver assigned ───
    public void sendDriverAssignedNotification(Order order) {
        if (order.getOfflineCustomerPhone() == null) return;
        if (order.getDriver() == null) return;

        String trackingUrl = baseUrl + "/tracking/public/" + order.getTrackingCode();
        String driverName = order.getDriver().getFullName();
        String vehicleType = order.getDriver().getVehicleType() != null
                ? order.getDriver().getVehicleType() : "vehicle";
        String plate = order.getDriver().getVehiclePlate() != null
                ? order.getDriver().getVehiclePlate() : "N/A";

        String message = "🚗 *Faster App — Driver On The Way!*\n\n"
                + "Your driver *" + driverName + "* is heading to you.\n"
                + "🚘 Vehicle: " + vehicleType + " | Plate: " + plate + "\n\n"
                + "📍 Track your order live:\n" + trackingUrl + "\n\n"
                + "Order: " + order.getTrackingCode() + "\n"
                + "Pay *$" + order.getGrandTotal() + "* cash on arrival.";

        sendMessage(order.getOfflineCustomerPhone(), message,
                MessageLog.MessageType.O2O_DRIVER_ASSIGNED,
                order.getId(), order.getTrackingCode(), defaultChannel());
    }

    // ── 3. Admin manually notifies driver of debt ─────
    public void sendDriverDebtNotification(User driver, String amountDue) {
        if (driver.getPhone() == null) return;

        String message = "💰 *Faster App — Commission Due*\n\n"
                + "Hello " + driver.getFullName() + ",\n\n"
                + "Your outstanding commission balance is: *$" + amountDue + "*\n\n"
                + "Please settle via:\n• OMT\n• WishMoney\n\n"
                + "After paying, send your receipt to the admin on "
                + "WhatsApp to reactivate your account.\n\n"
                + "Thank you for being a Faster driver! 🚀";

        sendMessage(driver.getPhone(), message,
                MessageLog.MessageType.DRIVER_DEBT_NOTIFICATION,
                null, null, defaultChannel());
    }

    // ── 4. Platform announcement (broadcast) ──────────
    // Used for account-blocked notices, offers, general
    // announcements — anything admin sends to one or many
    // users. Caller loops over recipients; this sends one.
    public void sendPlatformAnnouncement(String phone, String announcementText) {
        if (phone == null || phone.isBlank()) return;

        String message = "📢 *Faster App — Announcement*\n\n"
                + announcementText + "\n\n— The Faster Team";

        sendMessage(phone, message,
                MessageLog.MessageType.PLATFORM_ANNOUNCEMENT,
                null, null, defaultChannel());
    }

    // ── 5. OTP for phone verification ─────────────────
    // Overload without channel = use the default (WhatsApp).
    public void sendOtpMessage(String phone, String messageBody) {
        sendOtpMessage(phone, messageBody, defaultChannel());
    }

    // FIX: NEW — explicit channel choice. Called when the
    // user taps "Resend via SMS instead" after not receiving
    // the WhatsApp OTP (or vice versa). See AuthService.resendOtp().
    public void sendOtpMessage(String phone, String messageBody, Channel channel) {
        if (phone == null || phone.isBlank()) return;
        sendMessage(phone, messageBody,
                MessageLog.MessageType.OTP_VERIFICATION,
                null, null, channel);
    }

    // ─────────────────────────────────────────────────
    // CORE SEND — routes to WhatsApp or SMS
    // ─────────────────────────────────────────────────
    private void sendMessage(
            String toPhone, String body, MessageLog.MessageType type,
            Long orderId, String trackingCode, Channel channel) {

        MessageLog msgLog = MessageLog.builder()
                .recipientPhone(toPhone)
                .messageType(type)
                .provider("vonage")
                .channel(channel.name())
                .messageBody(body)
                .status(MessageLog.DeliveryStatus.PENDING)
                .relatedOrderId(orderId)
                .trackingCode(trackingCode)
                .build();

        msgLog = messageLogRepository.save(msgLog);

        try {
            String providerMessageId = (channel == Channel.WHATSAPP)
                    ? sendViaVonageWhatsApp(toPhone, body)
                    : sendViaVonageSms(toPhone, body);

            msgLog.setStatus(MessageLog.DeliveryStatus.SENT);
            msgLog.setProviderMessageId(providerMessageId);
            messageLogRepository.save(msgLog);

            log.info("✅ Message sent via vonage/{} to {} | type={} | id={}",
                    channel, toPhone, type, providerMessageId);

        } catch (Exception e) {
            msgLog.setStatus(MessageLog.DeliveryStatus.FAILED);
            msgLog.setErrorMessage(e.getMessage());
            messageLogRepository.save(msgLog);

            log.error("❌ Message failed via vonage/{} to {} | type={} | error={}",
                    channel, toPhone, type, e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────
    // VONAGE MESSAGES API — WhatsApp (JWT auth)
    //
    //   POST https://api.nexmo.com/v1/messages
    //   Authorization: Bearer <JWT signed with private key>
    //
    // The JWT's "application_id" claim + the private key's
    // matching public key (registered on the Vonage
    // Application) is what authenticates the request —
    // there is no separate API secret for this channel.
    // ─────────────────────────────────────────────────
    private String sendViaVonageWhatsApp(String toPhone, String body) {
        String url = "https://api.nexmo.com/v1/messages";

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setBearerAuth(generateVonageJwt());

        String normalizedTo = normalizePhone(toPhone).replace("+", "");
        String fromNumber = vonageWhatsAppFrom.replace("whatsapp:", "").replace("+", "");

        Map<String, Object> requestBody = new HashMap<>();
        requestBody.put("message_type", "text");
        requestBody.put("text", body);
        requestBody.put("to", Map.of("type", "whatsapp", "number", normalizedTo));
        requestBody.put("from", Map.of("type", "whatsapp", "number", fromNumber));
        requestBody.put("channel", "whatsapp");

        HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestBody, headers);

        ResponseEntity<Map> response = restTemplate.exchange(
                url, HttpMethod.POST, entity, Map.class);

        Map<?, ?> responseBody = response.getBody();
        if (responseBody == null || responseBody.get("message_uuid") == null) {
            throw new RuntimeException(
                    "Vonage WhatsApp returned empty response: " + response.getStatusCode());
        }

        return responseBody.get("message_uuid").toString();
    }

    // ─────────────────────────────────────────────────
    // VONAGE SMS API — Alphanumeric Sender ID (api_key/secret)
    //
    //   POST https://rest.nexmo.com/sms/json
    //
    // Used as the fallback/alternate channel when the
    // customer chooses "resend via SMS" — or could become
    // primary again in markets where WhatsApp isn't viable.
    // ─────────────────────────────────────────────────
    private String sendViaVonageSms(String toPhone, String body) {
        String url = "https://rest.nexmo.com/sms/json";

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        String normalizedTo = normalizePhone(toPhone).replace("+", "");

        Map<String, String> requestBody = new HashMap<>();
        requestBody.put("api_key", vonageApiKey);
        requestBody.put("api_secret", vonageApiSecret);
        requestBody.put("to", normalizedTo);
        requestBody.put("from", vonageSmsSender);
        requestBody.put("text", body);

        HttpEntity<Map<String, String>> entity = new HttpEntity<>(requestBody, headers);

        ResponseEntity<Map> response = restTemplate.exchange(
                url, HttpMethod.POST, entity, Map.class);

        Map<?, ?> responseBody = response.getBody();
        if (responseBody == null) {
            throw new RuntimeException("Vonage SMS returned empty response");
        }

        @SuppressWarnings("unchecked")
        java.util.List<Map<?, ?>> messages =
                (java.util.List<Map<?, ?>>) responseBody.get("messages");

        if (messages == null || messages.isEmpty()) {
            throw new RuntimeException("Vonage SMS returned no messages in response");
        }

        Map<?, ?> first = messages.get(0);
        String status = String.valueOf(first.get("status"));

        if (!"0".equals(status)) {
            Object errorObj = first.get("error-text");
            String error = errorObj != null ? errorObj.toString() : "Unknown error";
            throw new RuntimeException(
                    "Vonage SMS error: " + error + " (status=" + status + ")");
        }

        return String.valueOf(first.get("message-id"));
    }

    // ─────────────────────────────────────────────────
    // VONAGE JWT — signs a short-lived (15 min) RS256 JWT
    // using the Application's private key. Required for
    // every Messages API (WhatsApp) call.
    // ─────────────────────────────────────────────────
    private String generateVonageJwt() {
        try {
            PrivateKey privateKey = loadPrivateKey();

            Instant now = Instant.now();

            return Jwts.builder()
                    .setIssuedAt(java.util.Date.from(now))
                    .setExpiration(java.util.Date.from(now.plusSeconds(900)))
                    .setId(UUID.randomUUID().toString())
                    .claim("application_id", vonageApplicationId)
                    .signWith(privateKey, SignatureAlgorithm.RS256)
                    .compact();

        } catch (Exception e) {
            throw new RuntimeException(
                    "Failed to generate Vonage JWT: " + e.getMessage(), e);
        }
    }

    private PrivateKey loadPrivateKey() throws Exception {
        String pem = Files.readString(Paths.get(vonagePrivateKeyPath), StandardCharsets.UTF_8);

        String cleaned = pem
                .replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replaceAll("\\s", "");

        byte[] keyBytes = Base64.getDecoder().decode(cleaned);
        PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(keyBytes);
        KeyFactory keyFactory = KeyFactory.getInstance("RSA");
        return keyFactory.generatePrivate(keySpec);
    }

    // ─────────────────────────────────────────────────
    // MESSAGE BUILDER — O2O full message
    // ─────────────────────────────────────────────────
    private String buildO2OMessage(Order order, String trackingUrl) {
        String merchantName = order.getMerchant() != null
                ? order.getMerchant().getFullName() : "Store";

        String area = order.getDeliveryAddress() != null
                ? order.getDeliveryAddress()
                : order.getOfflineCustomerLandmark() != null
                    ? order.getOfflineCustomerLandmark() : "Your location";

        String createdTime = order.getCreatedAt() != null
                ? order.getCreatedAt().format(DateTimeFormatter.ofPattern("hh:mm a"))
                : "just now";

        return "👋 *Welcome to Faster App!*\n\n"
                + "Your order from *" + merchantName + "* has been placed at "
                + createdTime + ".\n\n"
                + "─────────────────\n📦 *Order Details*\n─────────────────\n"
                + "🔖 Order: *" + order.getTrackingCode() + "*\n"
                + "📍 Delivery to: " + area + "\n"
                + "💰 Total to pay: *$" + order.getGrandTotal() + "* cash\n\n"
                + "📲 *Track your order live:*\n" + trackingUrl + "\n\n"
                + "We are finding the nearest driver for you. You will "
                + "receive another message when your driver is on the way. 🚗\n\n"
                + "— Faster Team";
    }

    // ─────────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────────
    private Channel defaultChannel() {
        try {
            return Channel.valueOf(defaultChannelName.toUpperCase());
        } catch (Exception e) {
            return Channel.WHATSAPP;
        }
    }

    private String normalizePhone(String phone) {
        if (phone == null) return "";
        phone = phone.trim().replaceAll("\\s+", "");
        if (!phone.startsWith("+")) {
            return "+" + phone;
        }
        return phone;
    }
}