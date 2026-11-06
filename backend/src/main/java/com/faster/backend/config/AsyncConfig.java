package com.faster.backend.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

import java.util.concurrent.Executor;

// ─────────────────────────────────────────────────────
// AsyncConfig
//
// @EnableAsync (BackendApplication) was added so
// PushNotificationService.sendToUser could stop holding a DB row
// lock across the blocking Firebase HTTP call — but with no
// executor bean defined, Spring falls back to
// SimpleAsyncTaskExecutor, which spawns a brand-new, unpooled OS
// thread for every single @Async call instead of reusing a bounded
// pool. A burst of order-status changes (many drivers notified at
// once, or a slow Firebase endpoint) would then create unbounded
// concurrent threads with no queueing or cap — trading the
// original lock-holding problem for an unbounded-thread one.
// ─────────────────────────────────────────────────────
@Configuration
public class AsyncConfig {

    @Bean(name = "pushNotificationExecutor")
    public Executor pushNotificationExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(4);
        executor.setMaxPoolSize(16);
        executor.setQueueCapacity(200);
        executor.setThreadNamePrefix("push-notif-");
        executor.initialize();
        return executor;
    }
}
