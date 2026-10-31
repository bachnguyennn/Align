package com.bachnguyennn.align.server;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.security.servlet.UserDetailsServiceAutoConfiguration;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

/**
 * Align sync server (Phase 2, D-014/D-018). The app stays offline-first; this server only stores
 * what a device chooses to upload: session aggregates, sustained-tilt events and a settings
 * document. Contract: docs/agents/api-contracts.md.
 */
// No username/password users exist; excluding the default user also stops Boot from logging a
// generated password at startup.
@SpringBootApplication(exclude = UserDetailsServiceAutoConfiguration.class)
@ConfigurationPropertiesScan
public class AlignServerApplication {

    public static void main(String[] args) {
        SpringApplication.run(AlignServerApplication.class, args);
    }
}
