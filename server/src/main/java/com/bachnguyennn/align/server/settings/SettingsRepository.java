package com.bachnguyennn.align.server.settings;

import java.time.Instant;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface SettingsRepository extends JpaRepository<SettingsEntity, UUID> {

    /** Compare-and-set: writes only if the stored version is still {@code expected}. */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update SettingsEntity s
               set s.document = :document, s.version = s.version + 1, s.updatedAt = :now
             where s.deviceId = :deviceId and s.version = :expected""")
    int updateIfVersion(@Param("deviceId") UUID deviceId, @Param("expected") long expected,
            @Param("document") String document, @Param("now") Instant now);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from SettingsEntity s where s.deviceId = :deviceId")
    int deleteAllByDevice(@Param("deviceId") UUID deviceId);
}
