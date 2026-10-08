package com.faster.backend.service;

import com.faster.backend.entity.User;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.exception.NotFoundException;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class MerchantLocationService {

    private final UserRepository userRepository;

    @Transactional
    public User setLocation(Long merchantId, Double latitude,
                             Double longitude, String address) {

        User merchant = userRepository.findById(merchantId)
                .orElseThrow(() -> new NotFoundException("User not found"));

        if (merchant.getRole() != User.Role.MERCHANT) {
            throw new BusinessException(
                    "Only merchant accounts have a store location");
        }

        merchant.setStoreLatitude(latitude);
        merchant.setStoreLongitude(longitude);
        merchant.setStoreAddress(address);

        return userRepository.save(merchant);
    }

    public User getLocation(Long merchantId) {
        return userRepository.findById(merchantId)
                .orElseThrow(() -> new NotFoundException("User not found"));
    }
}
