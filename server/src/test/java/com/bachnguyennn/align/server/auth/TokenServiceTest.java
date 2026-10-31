package com.bachnguyennn.align.server.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Base64;
import java.util.HashSet;
import java.util.Set;
import org.junit.jupiter.api.Test;

class TokenServiceTest {

    private final TokenService tokens = new TokenService();

    @Test
    void tokensAre32RandomBytesInBase64Url() {
        Set<String> seen = new HashSet<>();
        for (int i = 0; i < 1000; i++) {
            String token = tokens.newToken();
            assertThat(token).hasSize(43).matches("[A-Za-z0-9_-]+");
            assertThat(Base64.getUrlDecoder().decode(token)).hasSize(32);
            assertThat(tokens.isWellFormed(token)).isTrue();
            seen.add(token);
        }
        assertThat(seen).hasSize(1000);
    }

    @Test
    void hashIsLowerCaseHexSha256() {
        // SHA-256("abc"), FIPS 180-2 test vector.
        assertThat(tokens.hash("abc"))
                .isEqualTo("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    }

    @Test
    void wellFormedRejectsOtherShapes() {
        assertThat(tokens.isWellFormed(null)).isFalse();
        assertThat(tokens.isWellFormed("")).isFalse();
        assertThat(tokens.isWellFormed("a".repeat(42))).isFalse();
        assertThat(tokens.isWellFormed("a".repeat(44))).isFalse();
        assertThat(tokens.isWellFormed("a".repeat(42) + "=")).isFalse();
        assertThat(tokens.isWellFormed("a".repeat(42) + "/")).isFalse();
    }

    @Test
    void hashComparisonIsExact() {
        String hash = tokens.hash(tokens.newToken());
        assertThat(tokens.hashesEqual(hash, hash)).isTrue();
        assertThat(tokens.hashesEqual(hash, tokens.hash(tokens.newToken()))).isFalse();
        assertThat(tokens.hashesEqual(hash, hash.substring(1))).isFalse();
    }
}
