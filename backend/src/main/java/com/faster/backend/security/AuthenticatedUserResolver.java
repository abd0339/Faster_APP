package com.faster.backend.security;

import com.faster.backend.entity.User;
import com.faster.backend.exception.NotFoundException;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Component;

/**
 * Resolves the authenticated principal (email or phone, per
 * AuthService.login) to the current User row.
 *
 * This exact lookup —
 * findByEmail, falling back to findByPhone, throwing NotFoundException
 * either way — was copy-pasted as a private helper in 11 different
 * controllers (StoreScheduleController, PlacesProxyController,
 * FeedbackController, CategoryController, LedgerController,
 * DriverController, OrderController, AdminController,
 * DeviceTokenController, OfferController, ItemController,
 * MerchantLocationController), each injecting UserRepository just for
 * this. One of them (PlacesProxyController) had already drifted by
 * null-checking `auth` first while the others didn't — a sign that
 * duplication, not just verbosity, was the actual cost. This is that
 * null-safe version, now the one copy.
 */
@Component
@RequiredArgsConstructor
public class AuthenticatedUserResolver {

    private final UserRepository userRepository;

    public User resolve(Authentication auth) {
        if (auth == null) {
            throw new NotFoundException("User not found");
        }
        String principal = auth.getName();
        return userRepository.findByEmail(principal)
                .or(() -> userRepository.findByPhone(principal))
                .orElseThrow(() -> new NotFoundException("User not found"));
    }

    public Long resolveId(Authentication auth) {
        return resolve(auth).getId();
    }

    /**
     * Same lookup, but returns null instead of throwing when the
     * principal can't be resolved. For the one caller (PlacesProxyController)
     * that uses this purely as a secondary rate-limit key on an
     * endpoint already behind anyRequest().authenticated() — a
     * failure to resolve shouldn't block the actual request, just
     * skip the per-user counter for it.
     */
    public Long resolveIdOrNull(Authentication auth) {
        if (auth == null) return null;
        String principal = auth.getName();
        return userRepository.findByEmail(principal)
                .or(() -> userRepository.findByPhone(principal))
                .map(User::getId)
                .orElse(null);
    }
}
