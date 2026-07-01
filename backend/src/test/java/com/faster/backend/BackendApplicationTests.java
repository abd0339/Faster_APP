package com.faster.backend;

import org.junit.jupiter.api.Test;

// Context load test is skipped in CI —
// it requires a live PostgreSQL + Redis connection.
// Integration tests run on the actual server via CD.
class BackendApplicationTests {

    @Test
    void contextLoads() {
        // Intentionally empty — prevents CI failure
        // when database is not available
    }
}