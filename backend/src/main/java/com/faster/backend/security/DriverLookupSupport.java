package com.faster.backend.security;

import com.faster.backend.entity.User;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.exception.NotFoundException;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * Looks up a user by id and verifies they're a DRIVER — this exact
 * "fetch by id (404 if missing), then verify role == DRIVER" check used
 * to be written out independently in AdminController.viewDriverDocument
 * (throwing NotFoundException/BusinessException, mapped by
 * GlobalExceptionHandler to 404/422) and CommunicationController
 * .notifyDriverDebt (returning a manual 400 with a different JSON
 * shape) — the identical business rule produced two different HTTP
 * contracts depending on which endpoint a client called. This is the
 * one copy, matching the codebase's established BusinessException/
 * NotFoundException convention.
 */
@Component
@RequiredArgsConstructor
public class DriverLookupSupport {

    private final UserRepository userRepository;

    public User findDriverOrThrow(Long driverId) {
        User user = userRepository.findById(driverId)
                .orElseThrow(() -> new NotFoundException("Driver not found"));
        if (user.getRole() != User.Role.DRIVER) {
            throw new BusinessException("This user is not a driver");
        }
        return user;
    }
}
