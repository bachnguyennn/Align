package com.bachnguyennn.align.server.session;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** Every query takes the device id: there is no way to read a session without its owner. */
public interface SessionRepository extends JpaRepository<SessionEntity, Long> {

    Optional<SessionEntity> findByDeviceIdAndSessionId(UUID deviceId, UUID sessionId);

    @Query("""
            select s from SessionEntity s
            where s.deviceId = :deviceId and s.updatedAt >= :since
            order by s.updatedAt asc, s.sessionId asc""")
    List<SessionEntity> findFirstPage(@Param("deviceId") UUID deviceId, @Param("since") Instant since,
            Pageable page);

    @Query("""
            select s from SessionEntity s
            where s.deviceId = :deviceId and s.updatedAt >= :since
              and (s.updatedAt > :afterUpdatedAt
                   or (s.updatedAt = :afterUpdatedAt and s.sessionId > :afterSessionId))
            order by s.updatedAt asc, s.sessionId asc""")
    List<SessionEntity> findPageAfter(@Param("deviceId") UUID deviceId, @Param("since") Instant since,
            @Param("afterUpdatedAt") Instant afterUpdatedAt, @Param("afterSessionId") UUID afterSessionId,
            Pageable page);

    @Query("""
            select s from SessionEntity s
            where s.deviceId = :deviceId and s.startedAt >= :fromInclusive and s.startedAt < :toExclusive""")
    List<SessionEntity> findStartedBetween(@Param("deviceId") UUID deviceId,
            @Param("fromInclusive") Instant fromInclusive, @Param("toExclusive") Instant toExclusive);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from SessionEntity s where s.deviceId = :deviceId")
    int deleteAllByDevice(@Param("deviceId") UUID deviceId);
}
