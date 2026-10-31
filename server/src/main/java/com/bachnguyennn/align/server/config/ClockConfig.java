package com.bachnguyennn.align.server.config;

import java.time.Clock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration(proxyBeanMethods = false)
public class ClockConfig {

    /** Server time source (UTC). A bean so tests could replace it. */
    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }
}
