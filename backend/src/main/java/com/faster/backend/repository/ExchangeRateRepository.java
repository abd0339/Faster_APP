package com.faster.backend.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.faster.backend.entity.ExchangeRate;

@Repository
public interface ExchangeRateRepository extends JpaRepository<ExchangeRate, Long> {
    // No custom methods needed — the single row (id = 1L) is
    // always accessed via the inherited findById/save.
}
