package com.bachnguyennn.align.server;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Connection;
import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

/**
 * Reports which database the suite ran on. CI sets ALIGN_TEST_EXPECT_DATABASE=PostgreSQL so that
 * a misconfigured job cannot silently fall back to H2 and still pass.
 */
class DatabaseEngineTest extends ApiTestSupport {

    @Autowired
    DataSource dataSource;
    @Autowired
    Flyway flyway;

    @Test
    void runsOnTheExpectedDatabaseWithAllMigrationsApplied() throws Exception {
        String product;
        String version;
        try (Connection connection = dataSource.getConnection()) {
            product = connection.getMetaData().getDatabaseProductName();
            version = connection.getMetaData().getDatabaseProductVersion();
        }
        System.out.println("[align-server tests] database: " + product + " " + version);

        String expected = System.getenv("ALIGN_TEST_EXPECT_DATABASE");
        if (expected != null && !expected.isBlank()) {
            assertThat(product).isEqualToIgnoringCase(expected);
        }
        assertThat(flyway.info().pending()).isEmpty();
        assertThat(flyway.info().applied()).isNotEmpty();
        assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("1");
    }
}
