package com.faster.backend.dto;

import com.faster.backend.entity.User;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AdminUserResponse {

    private Long id;
    private String fullName;
    private String email;
    private String phone;
    private User.Role role;
    private Boolean isActive;
    private Boolean isBlocked;
    private Boolean isEmailVerified;
    private BigDecimal debtAmount;
    private User.DriverMode driverMode;
    private Boolean isOnline;
    private LocalDateTime createdAt;
    private String verificationStatus;
    private String vehicleType;
    private String vehiclePlate;

    // NEW — booleans only, never raw file paths. Admin UI
    // uses these to decide which "view document" buttons to
    // show; the actual bytes are fetched through the
    // authenticated GET /api/admin/drivers/{id}/documents/{type}
    // endpoint using driverId + docType, never a stored path.
    private Boolean hasProfilePhoto;
    private Boolean hasNationalId;
    private Boolean hasLicenseFront;
    private Boolean hasLicenseBack;

    // ─── Build from User entity ───────────────────────
    public static AdminUserResponse from(User user) {
        return AdminUserResponse.builder()
                .id(user.getId())
                .fullName(user.getFullName())
                .email(user.getEmail())
                .phone(user.getPhone())
                .role(user.getRole())
                .isActive(user.getIsActive())
                .isBlocked(user.getIsBlocked())
                .isEmailVerified(user.getIsEmailVerified())
                .debtAmount(user.getDebtAmount())
                .driverMode(user.getDriverMode())
                .isOnline(user.getIsOnline())
                .createdAt(user.getCreatedAt())
                .verificationStatus(
                    user.getVerificationStatus() != null 
                    ? user.getVerificationStatus().name()
                    : "PENDING")
                .vehicleType(user.getVehicleType())
                .vehiclePlate(user.getVehiclePlate())
                .hasProfilePhoto(user.getDriverPhotoUrl() != null)
                .hasNationalId(user.getNationalIdUrl() != null)
                .hasLicenseFront(user.getDriverLicenseFrontUrl() != null)
                .hasLicenseBack(user.getDriverLicenseBackUrl() != null)
                .build();
    }
}