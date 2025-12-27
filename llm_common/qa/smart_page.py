import asyncio
import logging
from typing import Optional
logger = logging.getLogger(__name__)

try:
    from playwright.async_api import Page
except ImportError:
    Page = None

class SmartPage:
    def __init__(self, page: Optional[Page] = None):
        self.page = page

    async def wait_for_stable_visual(self, timeout_ms: int = 10000) -> bool:
        if self.page:
            try:
                await self.page.wait_for_load_state("networkidle", timeout=timeout_ms)
            except Exception:
                logger.warning("Network idle timeout")
        return True
