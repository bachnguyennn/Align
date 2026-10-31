"""Align posture-detection reference implementation (executable spec for the Swift
`PostureDetection` module), synthetic fixture generator and evaluation.

The pipeline code (geometry, motion_filter, calibration, tilt, detector, reminder, monitor) uses
plain Python floats so that it can be mirrored line-for-line in Swift. numpy is only used by the
fixture generator and the evaluation.
"""

__version__ = "0.1.0"
