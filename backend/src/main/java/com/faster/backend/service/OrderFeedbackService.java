package com.faster.backend.service;

import com.faster.backend.entity.Order;
import com.faster.backend.entity.OrderFeedback;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.exception.ForbiddenException;
import com.faster.backend.exception.NotFoundException;
import com.faster.backend.repository.OrderFeedbackRepository;
import com.faster.backend.repository.OrderRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
public class OrderFeedbackService {

    private final OrderFeedbackRepository feedbackRepository;
    private final OrderRepository orderRepository;

    // ─────────────────────────────────────────────────
    // SUBMIT FEEDBACK
    // Only the order's own customer can submit, only once
    // per order, only after DELIVERED.
    // ─────────────────────────────────────────────────
    @Transactional
    public OrderFeedback submitFeedback(
            Long orderId,
            Long customerId,
            Boolean driverThumbsUp,
            String negativeNote,
            Integer driverStars,
            Integer merchantStars) {

        Order order = orderRepository.findById(orderId)
                .orElseThrow(() -> new NotFoundException("Order not found"));

        if (order.getCustomer() == null
                || !order.getCustomer().getId().equals(customerId)) {
            throw new ForbiddenException(
                    "Not authorized to leave feedback for this order");
        }

        if (order.getStatus() != Order.OrderStatus.DELIVERED) {
            throw new BusinessException(
                    "Feedback can only be left after the order is delivered");
        }

        if (feedbackRepository.existsByOrderId(orderId)) {
            throw new BusinessException(
                    "Feedback has already been submitted for this order");
        }

        // Negative feedback requires an explanatory note —
        // this is the one hard rule, everything else is optional
        if (Boolean.FALSE.equals(driverThumbsUp)
                && (negativeNote == null || negativeNote.isBlank())) {
            throw new BusinessException(
                    "Please explain what went wrong so we can help");
        }

        if (driverStars != null && (driverStars < 1 || driverStars > 5)) {
            throw new BusinessException("Driver rating must be 1-5 stars");
        }
        if (merchantStars != null && (merchantStars < 1 || merchantStars > 5)) {
            throw new BusinessException("Merchant rating must be 1-5 stars");
        }

        OrderFeedback feedback = OrderFeedback.builder()
                .orderId(orderId)
                .customerId(customerId)
                .driverId(order.getDriver() != null
                        ? order.getDriver().getId() : null)
                .merchantId(order.getMerchant() != null
                        ? order.getMerchant().getId() : null)
                .driverThumbsUp(driverThumbsUp)
                .negativeNote(negativeNote)
                .driverStars(driverStars)
                .merchantStars(merchantStars)
                .resolved(false)
                .build();

        return feedbackRepository.save(feedback);
    }

    // ─────────────────────────────────────────────────
    // ADMIN — list everything, newest first
    // ─────────────────────────────────────────────────
    public List<OrderFeedback> getAllFeedback() {
        return feedbackRepository.findAllByOrderByCreatedAtDesc();
    }

    // ─────────────────────────────────────────────────
    // ADMIN — the queue that actually needs attention
    // ─────────────────────────────────────────────────
    public List<OrderFeedback> getUnresolvedNegativeFeedback() {
        return feedbackRepository
                .findByDriverThumbsUpFalseAndResolvedFalseOrderByCreatedAtAsc();
    }

    // ─────────────────────────────────────────────────
    // ADMIN — mark a negative feedback item resolved
    // ─────────────────────────────────────────────────
    @Transactional
    public OrderFeedback resolveFeedback(Long feedbackId, Long adminId) {
        OrderFeedback feedback = feedbackRepository.findById(feedbackId)
                .orElseThrow(() -> new NotFoundException("Feedback not found"));

        feedback.setResolved(true);
        feedback.setResolvedAt(LocalDateTime.now());
        feedback.setResolvedByAdminId(adminId);

        return feedbackRepository.save(feedback);
    }

    // ─────────────────────────────────────────────────
    // Driver's average rating — used on driver profile /
    // admin driver detail view
    // ─────────────────────────────────────────────────
    public Map<String, Object> getDriverRatingSummary(Long driverId) {
        Double avg = feedbackRepository.getDriverAverageRating(driverId);
        Long count = feedbackRepository.getDriverRatingCount(driverId);
        return Map.of(
                "averageRating", Math.round(avg * 10) / 10.0,
                "ratingCount", count);
    }

    // ─────────────────────────────────────────────────
    // Merchant's average rating
    // ─────────────────────────────────────────────────
    public Map<String, Object> getMerchantRatingSummary(Long merchantId) {
        Double avg = feedbackRepository.getMerchantAverageRating(merchantId);
        Long count = feedbackRepository.getMerchantRatingCount(merchantId);
        return Map.of(
                "averageRating", Math.round(avg * 10) / 10.0,
                "ratingCount", count);
    }
}