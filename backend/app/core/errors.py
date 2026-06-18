from __future__ import annotations
from fastapi import HTTPException, status

def bad_request(message: str):
    raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)

def unauthorized(message: str = "Unauthorized"):
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=message)

def forbidden(message: str = "Forbidden"):
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=message)

def not_found(message: str = "Not found"):
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=message)

def conflict(message: str = "Conflict"):
    raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=message)

def bad_gateway(message: str = "Upstream service error"):
    raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=message)
