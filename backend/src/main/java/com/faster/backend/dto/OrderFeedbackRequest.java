package com.faster.backend.dto;

import lombok.Data;

/**
 * Body for POST /api/orders/{orderId}/feedback
 *
 * Every field is optional/nullable EXCEPT: if driverThumbsUp
 * is explicitly false, negativeNote becomes required (checked
 * in OrderFeedbackService, not here, since the requirement is
 * conditional). Sending an entirely empty body is valid and
 * matches the customer tapping "Skip" — nothing gets stored
 * in that case, see FeedbackController.
 */
@Data
public class OrderFeedbackRequest {

    // null = customer skipped the thumbs up/down entirely
    private Boolean driverThumbsUp;

    // Required only when driverThumbsUp == false
    private String negativeNote;

    // 1-5, or null if the customer skipped this specific rating
    private Integer driverStars;

    // 1-5, or null if the customer skipped this specific rating
    private Integer merchantStars;
}