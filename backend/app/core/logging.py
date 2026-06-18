from __future__ import annotations
import logging, sys

def configure_logging() -> None:
    logging.basicConfig(level=logging.INFO, stream=sys.stdout, format="%(levelname)s %(name)s %(message)s")

def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)
