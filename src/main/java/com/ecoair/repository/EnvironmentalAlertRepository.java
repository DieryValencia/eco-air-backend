package com.ecoair.repository;

import com.ecoair.model.EnvironmentalAlert;
import org.springframework.data.jpa.repository.JpaRepository;

public interface EnvironmentalAlertRepository extends JpaRepository<EnvironmentalAlert, Long> {
}
