package com.faster.backend.repository;

import com.faster.backend.entity.MessageLog;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface MessageLogRepository
        extends JpaRepository<MessageLog, Long> {

    // ─── Find all messages for a phone number ─────────
    // Used by admin to see all messages sent to a person
    List<MessageLog> findByRecipientPhoneOrderByCreatedAtDesc(
            String phone);

    // ─── Find all messages for an order ──────────────
    List<MessageLog> findByRelatedOrderIdOrderByCreatedAtDesc(
            Long orderId);

    // ─── Find by type ─────────────────────────────────
    List<MessageLog> findByMessageTypeOrderByCreatedAtDesc(
            MessageLog.MessageType type);

    // ─── Find failed messages ─────────────────────────
    // Used for retry logic or admin alerts
    List<MessageLog> findByStatusOrderByCreatedAtDesc(
            MessageLog.DeliveryStatus status);
}