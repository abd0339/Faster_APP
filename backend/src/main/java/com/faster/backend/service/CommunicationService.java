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
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;

import java.time.format.DateTimeFormatter;
import java.util.Map;

// ─────────────────────────────────────────────────────
// CommunicationService — Twilio ONLY.
//
// FIX: Vonage has been fully removed (account issues on
// their side made it unworkable). Twilio confirmed working
// with real delivered messages to 3 different Lebanese
// numbers after enabling Geo Permissions for Lebanon.
//
// Much simpler than Vonage here: BOTH channels use the same
// Messages API endpoint with simple Basic Auth (Account SID
// + Auth Token) — no JWT, no private key file to manage.
//
// TWO CHANNELS, CALLER CHOOSES:
//   Channel.WHATSAPP (default/primary) — sent via the
//     Twilio WhatsApp sandbox number for now. Swaps to a
//     real approved WhatsApp Business sender later by
//     changing one env var, no code change needed.
//   Channel.SMS (fallback/alternate) — sent through the
//     Messaging Service (alphanumeric sender "FasterApp"
//     with a real phone number as automatic fallback —
//     Twilio picks whichever actually works per destination
//     country, so Lebanon is handled correctly either way).
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

        public enum Channel {
                WHATSAPP, SMS
        }

        @Value("${app.base.url:http://localhost:8080}")
        private String baseUrl;

        @Value("${twilio.default-channel:WHATSAPP}")
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

        public void sendO2OTrackingLink(Order order) {
                if (order.getOfflineCustomerPhone() == null)
                        return;

                String trackingUrl = baseUrl + "/tracking/public/" + order.getTrackingCode();
                String message = buildO2OMessage(order, trackingUrl);

                sendMessage(order.getOfflineCustomerPhone(), message,
                                MessageLog.MessageType.O2O_TRACKING_LINK,
                                order.getId(), order.getTrackingCode(), defaultChannel());
        }

        public void sendDriverAssignedNotification(Order order) {
                if (order.getOfflineCustomerPhone() == null)
                        return;
                if (order.getDriver() == null)
                        return;

                String trackingUrl = baseUrl + "/tracking/public/" + order.getTrackingCode();
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
                                + "📍 Track your order live:\n" + trackingUrl + "\n\n"
                                + "Order: " + order.getTrackingCode() + "\n"
                                + "Pay *$" + order.getGrandTotal() + "* cash on arrival.";

                sendMessage(order.getOfflineCustomerPhone(), message,
                                MessageLog.MessageType.O2O_DRIVER_ASSIGNED,
                                order.getId(), order.getTrackingCode(), defaultChannel());
        }

        public void sendDriverDebtNotification(User driver, String amountDue) {
                if (driver.getPhone() == null)
                        return;

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

        public void sendPlatformAnnouncement(String phone, String announcementText) {
                if (phone == null || phone.isBlank())
                        return;

                String message = "📢 *Faster App — Announcement*\n\n"
                                + announcementText + "\n\n— The Faster Team";

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
                if (phone == null)
                        return "";
                phone = phone.trim().replaceAll("\\s+", "");
                if (!phone.startsWith("+")) {
                        return "+" + phone;
                }
                return phone;
        }
}