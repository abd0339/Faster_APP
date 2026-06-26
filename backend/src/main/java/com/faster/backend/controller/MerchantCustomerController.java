package com.faster.backend.controller;

import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/merchant")
@RequiredArgsConstructor
public class MerchantCustomerController {

    private final UserRepository userRepository;

    // ─── GET /api/merchant/customer/lookup?phone=+96170... ───
    // Merchant uses this during O2O order creation to validate
    // whether the customer's phone is registered in the system.
    // Returns ONLY: found, fullName, phone — nothing else.
    // Merchant CANNOT see email, password, debt, or any other field.
    @GetMapping("/customer/lookup")
    public ResponseEntity<?> lookupCustomer(
            @RequestParam String phone) {

        return userRepository.findByPhone(phone)
                .filter(u -> u.getRole() == User.Role.CUSTOMER)
                .map(u -> ResponseEntity.ok(Map.of(
                        "found", true,
                        "fullName", u.getFullName(),
                        "phone", u.getPhone())))
                .orElse(ResponseEntity.ok(Map.of(
                        "found", false,
                        "phone", phone,
                        "message",
                        "Phone not registered — will create as offline customer")));
    }
}