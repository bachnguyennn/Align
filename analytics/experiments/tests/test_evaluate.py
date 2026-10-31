from align_reference.evaluate import axis_projection, build, glance_spec, hold_spec
from align_reference.fixtures import replay


def test_axis_projection_table_renders():
    text = axis_projection()
    assert text.startswith("| mount pitch/roll")
    assert "10/0" in text


def test_short_glance_never_reminds_and_long_hold_does():
    assert replay(build(glance_spec(1, 10.0))).reminders == []
    assert len(replay(build(hold_spec(1, forward=25.0, hold=45.0))).reminders) == 1
