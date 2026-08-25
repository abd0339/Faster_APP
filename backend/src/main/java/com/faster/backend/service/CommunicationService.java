package com.faster.backend.service;

import com.faster.backend.entity.MessageLog;
import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.repository.MessageLogRepository;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;

import java.time.format.DateTimeFormatter;
import java.util.Map;

// ─────────────────────────────────────────────────────
// CommunicationService — Twilio ONLY.
//
// FIX (channel default flipped): WhatsApp requires an
// approved Meta Message Template for any message to someone
// who hasn't messaged the business first — confirmed via
// real testing that this blocks OTP, tracking links, and
// broadcasts alike for brand-new recipients (error 63016,
// every time, no exceptions). No approved template exists
// yet. SMS has no such restriction and is proven 100%
// reliable for real Lebanese numbers. SMS is now the
// default/primary channel platform-wide; WhatsApp remains
// available and will become useful again once a Message
// Template is approved by Meta — a separate, future task.
//
// Much simpler than Vonage here: BOTH channels use the same
// Messages API endpoint with simple Basic Auth (Account SID
// + Auth Token) — no JWT, no private key file to manage.
//
// TWO CHANNELS, CALLER CHOOSES:
//   Channel.SMS (default/primary) — sent through the
//     Messaging Service (alphanumeric sender "FasterApp"
//     with a real phone number as automatic fallback —
//     Twilio picks whichever actually works per destination
//     country, so Lebanon is handled correctly either way).
//   Channel.WHATSAPP (available, not yet reliable for new
//     contacts) — sent via the approved WhatsApp Business
//     sender. Works fine for anyone who has messaged the
//     business first; fails with error 63016 for anyone who
//     hasn't, until a Message Template is approved.
//
// Every message is logged to message_logs (channel + status)
// for audit. A failed send NEVER throws back to the caller —
// logged and swallowed, so a broken provider can never block
// an order or registration from completing.
// ─────────────────────────────────────────────────────
@Slf4j
@Service
@RequiredArgsConstructor
public class CommunicationService {

        private final MessageLogRepository messageLogRepository;
        private final RestTemplate restTemplate;

        // NEW: used to check whether an "offline" recipient is really
        // already a registered user — if so we reach them by FREE push
        // instead of paid SMS. See sendO2OTrackingLink.
        private final UserRepository userRepository;
        private final PushNotificationService pushNotificationService;

        public enum Channel {
                WHATSAPP, SMS
        }

        @Value("${app.base.url:http://localhost:8080}")
        private String baseUrl;

        @Value("${twilio.default-channel:SMS}")
        private String defaultChannelName;

        // ─── Twilio credentials — same for both channels ──
        @Value("${twilio.account-sid:}")
        private String twilioAccountSid;

        @Value("${twilio.auth-token:}")
        private String twilioAuthToken;

        // ─── SMS — routed through the Messaging Service ───
        // Twilio automatically picks the Alphanumeric Sender
        // ("FasterApp") or the pooled phone number, whichever
        // actually works for the destination country.
        @Value("${twilio.messaging-service-sid:}")
        private String twilioMessagingServiceSid;

        private static final String TWILIO_MESSAGES_URL = "https://api.twilio.com/2010-04-01/Accounts/%s/Messages.json";

        // ─────────────────────────────────────────────────
        // PUBLIC API — message types the system sends
        // ─────────────────────────────────────────────────

        // ─────────────────────────────────────────────────
        // O2O TRACKING LINK — push first, SMS as fallback
        //
        // The recipient is "offline" only in the sense that the
        // SENDER typed their phone number instead of picking them
        // from a list. They may already be a user of this app.
        //
        // If they are, we reach them by FCM push — free, and with
        // live in-app tracking — instead of a ~$0.36 SMS. As the
        // user base grows the SMS bill SHRINKS rather than rising
        // with order volume.
        //
        // IMPORTANT (deadlock avoided): the push invites the
        // recipient to SHARE THEIR EXACT LOCATION, but this is
        // purely optional refinement. The order already has a
        // destination — the address the sender typed — and a
        // computed fee. If the recipient ignores the push entirely,
        // the delivery proceeds normally on the typed address.
        // Confirmation only makes the fee more accurate; it is
        // never required for the order to work.
        // ─────────────────────────────────────────────────
        public void sendO2OTrackingLink(Order order) {
                if (order.getOfflineCustomerPhone() == null
                                || order.getOfflineCustomerPhone().isBlank())
                        return;

                String trackingUrl = baseUrl + "/tracking/public/"
                                + order.getTrackingCode();

                var existingUser = userRepository
                                .findByPhone(order.getOfflineCustomerPhone());

                if (existingUser.isPresent()) {
                        User recipient = existingUser.get();

                        // Wording deliberately says "confirm" as an
                        // optional improvement, not a required step —
                        // the delivery is already going ahead.
                        pushNotificationService.sendToUser(
                                        recipient.getId(),
                                        "A delivery is on its way to you",
                                        "Order " + order.getTrackingCode()
                                                        + " - pay $" + order.getGrandTotal()
                                                        + " cash. Tap to track, or share your exact"
                                                        + " location to help your driver find you.",
                                        Map.of("type", "incoming_delivery",
                                                        "orderId", String.valueOf(order.getId()),
                                                        "trackingCode", order.getTrackingCode()));

                        // Logged like any other message so the admin
                        // audit trail still shows the recipient was
                        // contacted — just on a different channel.
                        messageLogRepository.save(MessageLog.builder()
                                        .recipientPhone(order.getOfflineCustomerPhone())
                                        .messageType(MessageLog.MessageType.O2O_TRACKING_LINK)
                                        .provider("fcm")
                                        .channel("PUSH")
                                        .messageBody("Incoming delivery push for "
                                                        + order.getTrackingCode())
                                        .status(MessageLog.DeliveryStatus.SENT)
                                        .relatedOrderId(order.getId())
                                        .trackingCode(order.getTrackingCode())
                                        .build());

                        log.info("✅ O2O recipient is a registered user - sent FREE "
                                        + "push instead of SMS (saved ~$0.36)");
                        return;
                }

                sendMessage(order.getOfflineCustomerPhone(),
                                buildO2OMessage(order, trackingUrl),
                                MessageLog.MessageType.O2O_TRACKING_LINK,
                                order.getId(), order.getTrackingCode(), defaultChannel());
        }

        // Same push-first rule as the tracking link above.
        public void sendDriverAssignedNotification(Order order) {
                if (order.getOfflineCustomerPhone() == null
                                || order.getOfflineCustomerPhone().isBlank())
                        return;
                if (order.getDriver() == null)
                        return;

                String trackingUrl = baseUrl + "/tracking/public/"
                                + order.getTrackingCode();
                String driverName = order.getDriver().getFullName();
                String vehicleType = order.getDriver().getVehicleType() != null
                                ? order.getDriver().getVehicleType()
                                : "vehicle";
                String plate = order.getDriver().getVehiclePlate() != null
                                ? order.getDriver().getVehiclePlate()
                                : "N/A";

                var existingUser = userRepository
                                .findByPhone(order.getOfflineCustomerPhone());

                if (existingUser.isPresent()) {
                        pushNotificationService.sendToUser(
                                        existingUser.get().getId(),
                                        "Your driver is on the way",
                                        driverName + " (" + vehicleType + ", " + plate
                                                        + ") is heading to you.",
                                        Map.of("type", "driver_assigned",
                                                        "orderId", String.valueOf(order.getId()),
                                                        "trackingCode", order.getTrackingCode()));
                        log.info("✅ Driver-assigned push sent free (saved ~$0.36)");
                        return;
                }

                // GSM-7, kept short — every ~153 chars adds a segment.
                sendMessage(order.getOfflineCustomerPhone(),
                                "Faster App: driver " + driverName + " (" + vehicleType
                                                + ", " + plate + ") is on the way. Track: "
                                                + trackingUrl,
                                MessageLog.MessageType.O2O_DRIVER_ASSIGNED,
                                order.getId(), order.getTrackingCode(), defaultChannel());
        }

        public void sendDriverDebtNotification(User driver, String amountDue) {
                if (driver.getPhone() == null)
                        return;

                // COST FIX: GSM-7 only. Note the old version also used
                // bullet characters, which are outside GSM-7 too.
                String message = "Faster App: hello " + driver.getFullName()
                                + ", your outstanding commission is $" + amountDue
                                + ". Please settle via OMT or WishMoney, then send"
                                + " your receipt to the admin on WhatsApp to"
                                + " reactivate your account.";

                sendMessage(driver.getPhone(), message,
                                MessageLog.MessageType.DRIVER_DEBT_NOTIFICATION,
                                null, null, defaultChannel());
        }

        public void sendPlatformAnnouncement(String phone, String announcementText) {
                if (phone == null || phone.isBlank())
                        return;

                // COST FIX: GSM-7 only. NOTE: announcementText itself
                // is admin-supplied — if an admin types emoji into a
                // broadcast, that message still goes UCS-2 and costs
                // multiple segments. Worth warning admins in the UI.
                String message = "Faster App: " + announcementText
                                + " - The Faster Team";

                sendMessage(phone, message,
                                MessageLog.MessageType.PLATFORM_ANNOUNCEMENT,
                                null, null, defaultChannel());
        }

        public void sendOtpMessage(String phone, String messageBody) {
                sendOtpMessage(phone, messageBody, defaultChannel());
        }

        // Explicit channel choice — called when the user taps
        // "Resend via SMS instead" after not receiving the
        // WhatsApp OTP. See AuthService.resendOtp().
        public void sendOtpMessage(String phone, String messageBody, Channel channel) {
                if (phone == null || phone.isBlank())
                        return;
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
                                .provider("twilio")
                                .channel(channel.name())
                                .messageBody(body)
                                .status(MessageLog.DeliveryStatus.PENDING)
                                .relatedOrderId(orderId)
                                .trackingCode(trackingCode)
                                .build();

                msgLog = messageLogRepository.save(msgLog);

                try {
                        String providerMessageId = (channel == Channel.WHATSAPP)
                                        ? sendViaTwilioWhatsApp(toPhone, body)
                                        : sendViaTwilioSms(toPhone, body);

                        msgLog.setStatus(MessageLog.DeliveryStatus.SENT);
                        msgLog.setProviderMessageId(providerMessageId);
                        messageLogRepository.save(msgLog);

                        log.info("✅ Message sent via twilio/{} to {} | type={} | id={}",
                                        channel, toPhone, type, providerMessageId);

                } catch (Exception e) {
                        msgLog.setStatus(MessageLog.DeliveryStatus.FAILED);
                        msgLog.setErrorMessage(e.getMessage());
                        messageLogRepository.save(msgLog);

                        log.error("❌ Message failed via twilio/{} to {} | type={} | error={}",
                                        channel, toPhone, type, e.getMessage());
                }
        }

        // ─────────────────────────────────────────────────
        // TWILIO SMS — via Messaging Service
        // Twilio automatically selects the Alphanumeric Sender
        // ("FasterApp") or falls back to the pooled phone number
        // depending on what the destination country supports.
        // ─────────────────────────────────────────────────
        private String sendViaTwilioSms(String toPhone, String body) {
                String url = String.format(TWILIO_MESSAGES_URL, twilioAccountSid);

                MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
                form.add("To", normalizePhone(toPhone));
                form.add("MessagingServiceSid", twilioMessagingServiceSid);
                form.add("Body", body);

                return postToTwilio(url, form);
        }

        // ─────────────────────────────────────────────────
        // TWILIO WHATSAPP — via the same Messaging Service pool
        // FIX: your WhatsApp Business sender (+17124301474,
        // "Faster Delivery App") is now registered IN the same
        // Messaging Service senders pool as the SMS senders —
        // no more sandbox, no more hardcoded number. Twilio
        // auto-routes to the WhatsApp-capable sender in the pool
        // whenever "To" has a whatsapp: prefix, exactly like it
        // auto-picks Alphanumeric vs phone number for plain SMS.
        // ─────────────────────────────────────────────────
        private String sendViaTwilioWhatsApp(String toPhone, String body) {
                String url = String.format(TWILIO_MESSAGES_URL, twilioAccountSid);

                MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
                form.add("To", "whatsapp:" + normalizePhone(toPhone));
                form.add("MessagingServiceSid", twilioMessagingServiceSid);
                form.add("Body", body);

                return postToTwilio(url, form);
        }

        private String postToTwilio(String url, MultiValueMap<String, String> form) {
                HttpHeaders headers = new HttpHeaders();
                headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
                headers.setBasicAuth(twilioAccountSid, twilioAuthToken);

                HttpEntity<MultiValueMap<String, String>> entity = new HttpEntity<>(form, headers);

                ResponseEntity<Map> response = restTemplate.exchange(
                                url, HttpMethod.POST, entity, Map.class);

                Map<?, ?> responseBody = response.getBody();
                if (responseBody == null || responseBody.get("sid") == null) {
                        throw new RuntimeException(
                                        "Twilio returned empty response: " + response.getStatusCode());
                }

                Object errorCode = responseBody.get("error_code");
                if (errorCode != null) {
                        Object errorMsg = responseBody.get("error_message");
                        throw new RuntimeException(
                                        "Twilio error " + errorCode + ": " + errorMsg);
                }

                return responseBody.get("sid").toString();
        }

        // ─────────────────────────────────────────────────
        // MESSAGE BUILDER — O2O full message
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
                                ? order.getCreatedAt().format(DateTimeFormatter.ofPattern("hh:mm a"))
                                : "just now";

                // COST FIX: this was by far the most expensive message
                // on the platform — multiple emoji PLUS box-drawing
                // characters (─), all outside GSM-7, forcing UCS-2 at
                // 67 chars/segment on a ~380 character message. That
                // billed as roughly SIX segments (~$2.16 to Lebanon)
                // for every single O2O order placed. This GSM-7
                // version fits in about two segments.
                return "Faster App: your order from " + merchantName
                                + " was placed at " + createdTime + ". Order "
                                + order.getTrackingCode() + ". Delivery to " + area
                                + ". Total to pay: $" + order.getGrandTotal()
                                + " cash. We are finding the nearest driver -"
                                + " you will get another message when the driver"
                                + " is on the way. Track: " + trackingUrl;
        }

        // ─────────────────────────────────────────────────
        // HELPERS
        // ─────────────────────────────────────────────────
        private Channel defaultChannel() {
                try {
                        return Channel.valueOf(defaultChannelName.toUpperCase());
                } catch (Exception e) {
                        // Fallback if the configured value is invalid —
                        // SMS, matching the platform default (WhatsApp
                        // is blocked by Meta for new contacts).
                        return Channel.SMS;
                }
        }

        private String normalizePhone(String phone) {
                if (phone == null)
                        return "";
                phone = phone.trim().replaceAll("\\s+", "");
                if (!phone.startsWith("+")) {
                        return "+" + phone;
                }
                return phone;
        }
}
