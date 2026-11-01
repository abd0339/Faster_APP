package com.faster.backend.service;

import com.faster.backend.entity.StoreSchedule;
import com.faster.backend.entity.User;
import com.faster.backend.exception.NotFoundException;
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
                .orElseThrow(() -> new NotFoundException(
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
    //
    // FIX (review 2026-11-01): this used to only check today's
    // schedule against [openTime, closeTime] on the same calendar
    // day, which is wrong for any schedule crossing midnight (e.g.
    // open 18:00 / close 02:00 — common for Lebanese restaurants and
    // night venues). At 01:00 the store should read "open" (last
    // night's hours haven't ended yet), but 01:00 isBefore 18:00, so
    // the old check always said "closed" for the entire post-midnight
    // window. setSchedule() never rejected closeTime < openTime
    // either, so this bad-looking-but-intentional state was easy to
    // create and nothing downstream corrected for it.
    //
    // Fix: a schedule where closeTime is before openTime describes an
    // overnight window that continues into the NEXT calendar day, so
    // "open now" has to check two schedule rows: today's (covering
    // the evening-to-midnight portion) and yesterday's (covering any
    // midnight-to-closeTime portion still running from last night).
    public boolean isStoreOpenNow(Long merchantId) {
        // Get current day/time in Beirut timezone
        ZonedDateTime now = ZonedDateTime.now(
            ZoneId.of("Asia/Beirut"));
        LocalTime nowTime = now.toLocalTime();

        StoreSchedule.DayOfWeek today = toScheduleDay(now.getDayOfWeek());
        StoreSchedule.DayOfWeek yesterday = toScheduleDay(now.getDayOfWeek().minus(1));

        boolean openByTodaysSchedule = scheduleRepository
                .findOpenSchedule(merchantId, today)
                .map(s -> isOpenAt(s, nowTime, true))
                .orElse(false);

        boolean openByLastNightsSchedule = scheduleRepository
                .findOpenSchedule(merchantId, yesterday)
                .map(s -> isOpenAt(s, nowTime, false))
                .orElse(false);

        return openByTodaysSchedule || openByLastNightsSchedule;
    }

    // isToday=true: checking a schedule against ITS OWN day — the
    // normal case is nowTime within [open, close]; a midnight-crossing
    // schedule (close < open) is instead open from openTime onward
    // (the portion that continues past midnight into tomorrow).
    //
    // isToday=false: checking YESTERDAY's schedule for overnight
    // continuation — only relevant if it crosses midnight, in which
    // case it's still open until closeTime this morning.
    private boolean isOpenAt(StoreSchedule s, LocalTime nowTime, boolean isToday) {
        boolean crossesMidnight = s.getCloseTime().isBefore(s.getOpenTime());

        if (isToday) {
            if (!crossesMidnight) {
                return !nowTime.isBefore(s.getOpenTime())
                        && !nowTime.isAfter(s.getCloseTime());
            }
            return !nowTime.isBefore(s.getOpenTime());
        } else {
            return crossesMidnight && !nowTime.isAfter(s.getCloseTime());
        }
    }

    private StoreSchedule.DayOfWeek toScheduleDay(DayOfWeek javaDow) {
        return StoreSchedule.DayOfWeek.valueOf(javaDow.name());
    }
}
