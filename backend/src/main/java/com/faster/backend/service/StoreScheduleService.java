package com.faster.backend.service;

import com.faster.backend.entity.StoreSchedule;
import com.faster.backend.entity.User;
import com.faster.backend.repository.StoreScheduleRepository;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.DayOfWeek;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class StoreScheduleService {

    private final StoreScheduleRepository scheduleRepository;
    private final UserRepository userRepository;

    // ─── Set schedule for one day ─────────────────────
    @Transactional
    public StoreSchedule setSchedule(
            Long merchantId,
            StoreSchedule.DayOfWeek day,
            LocalTime openTime,
            LocalTime closeTime,
            Boolean isClosed) {

        User merchant = userRepository.findById(merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Merchant not found"));

        // Update if exists, create if not
        StoreSchedule schedule = scheduleRepository
                .findByMerchantIdAndDayOfWeek(
                    merchantId, day)
                .orElse(StoreSchedule.builder()
                    .merchant(merchant)
                    .dayOfWeek(day)
                    .build());

        schedule.setOpenTime(openTime);
        schedule.setCloseTime(closeTime);
        schedule.setIsClosed(
            isClosed != null ? isClosed : false);

        return scheduleRepository.save(schedule);
    }

    // ─── Get full weekly schedule ─────────────────────
    public List<StoreSchedule> getSchedule(
            Long merchantId) {
        return scheduleRepository
            .findByMerchantIdOrderByDayOfWeekAsc(
                merchantId);
    }

    // ─── Is the store open RIGHT NOW? ─────────────────
    public boolean isStoreOpenNow(Long merchantId) {
        // Get current day in Beirut timezone
        ZonedDateTime now = ZonedDateTime.now(
            ZoneId.of("Asia/Beirut"));

        DayOfWeek javaDow = now.getDayOfWeek();
        StoreSchedule.DayOfWeek day =
            StoreSchedule.DayOfWeek.valueOf(
                javaDow.name());

        return scheduleRepository
                .findOpenSchedule(merchantId, day)
                .map(s -> {
                    LocalTime nowTime =
                        now.toLocalTime();
                    return !nowTime.isBefore(
                                s.getOpenTime())
                        && !nowTime.isAfter(
                                s.getCloseTime());
                })
                .orElse(false);
    }
}
