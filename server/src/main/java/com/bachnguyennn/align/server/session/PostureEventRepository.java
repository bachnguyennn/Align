package com.bachnguyennn.align.server.session;

import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface PostureEventRepository extends JpaRepository<PostureEventEntity, Long> {

    @Query("select e from PostureEventEntity e where e.deviceId = :deviceId and e.eventId in :eventIds")
    List<PostureEventEntity> findByDeviceAndEventIds(@Param("deviceId") UUID deviceId,
            @Param("eventIds") Collection<UUID> eventIds);

    @Query("select e from PostureEventEntity e where e.sessionPk = :sessionPk order by e.startedAt asc, e.eventId asc")
    List<PostureEventEntity> findBySession(@Param("sessionPk") Long sessionPk);

    long countBySessionPk(Long sessionPk);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from PostureEventEntity e where e.deviceId = :deviceId")
    int deleteAllByDevice(@Param("deviceId") UUID deviceId);
}
