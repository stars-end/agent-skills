#!/usr/bin/env python3
"""Run Prime Radiant UI smoke tests using GLM-4.6V agent.

This script:
1. Loads story specs from docs/TESTING/STORIES/
2. Creates a Playwright browser and GLM client
3. Runs each story using UISmokeAgent
4. Produces a JSON report of findings

Environment variables required:
- ZAI_API_KEY: Z.AI API key for GLM-4.6V
- PRIME_SMOKE_BASE_URL: Frontend URL to test (e.g., https://app.primeradiant.ai)
"""

import asyncio
import json
import logging
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# Local imports
from browser_adapter import create_browser_context

# LLM Common imports
from llm_common.agents import (
    GLMConfig, 
    GLMVisionClient, 
    load_stories_from_directory, 
    UISmokeAgent,
)
from llm_common.agents.models import SmokeRunReport

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[logging.StreamHandler()],
)
logger = logging.getLogger(__name__)


def dataclass_to_dict(obj):
    """Convert dataclass instances to dicts for JSON serialization."""
    if hasattr(obj, "__dataclass_fields__"):
        return {k: dataclass_to_dict(v) for k, v in obj.__dict__.items()}
    elif isinstance(obj, list):
        return [dataclass_to_dict(item) for item in obj]
    elif isinstance(obj, dict):
        return {k: dataclass_to_dict(v) for k, v in obj.items()}
    else:
        return obj


async def main():
    """Run smoke tests and generate report."""
    # Validate environment
    api_key = os.environ.get("ZAI_API_KEY")
    base_url = os.environ.get("PRIME_SMOKE_BASE_URL")

    if not api_key:
        logger.error("ZAI_API_KEY environment variable not set")
        sys.exit(1)

    if not base_url:
        logger.error("PRIME_SMOKE_BASE_URL environment variable not set")
        sys.exit(1)

    logger.info(f"Starting Prime Radiant smoke tests against {base_url}")

    # Initialize GLM client
    glm_config = GLMConfig(api_key=api_key, model="glm-4.6v")
    glm_client = GLMVisionClient(glm_config)

    # Load stories
    stories_dir = Path(__file__).parent.parent.parent / "docs" / "TESTING" / "STORIES"

    if not stories_dir.exists():
        logger.error(f"Stories directory not found: {stories_dir}")
        sys.exit(1)

    stories = load_stories_from_directory(stories_dir)
    if not stories:
        logger.error("No stories found")
        sys.exit(1)

    logger.info(f"Loaded {len(stories)} stories")

    # Check for saved auth state
    auth_state_file = Path(__file__).parent.parent.parent / ".playwright-auth" / "state.json"
    storage_state = str(auth_state_file) if auth_state_file.exists() else None
    
    if storage_state:
        logger.info(f"♻️ Using saved auth state from: {auth_state_file}")
    else:
        logger.warning("⚠️ No auth state found - login may be required")
        logger.warning(f"  Run verify_auth_and_dashboard.py first to generate auth state")

    # Create browser with auth state
    logger.info("Launching browser...")
    headless = os.environ.get("HEADLESS", "true").lower() == "true"
    browser, adapter = await create_browser_context(
        base_url, 
        headless=headless,
        storage_state=storage_state,
    )
    
    # === bd-svki: Hybrid login check ===
    # Auth state is domain-bound (localhost vs Railway). Check if we need to login.
    logger.info("Checking authentication status...")
    try:
        await adapter.navigate("/")
        await asyncio.sleep(2)  # Brief wait for page load
        
        # Check for Clerk sign-in button (indicates not logged in)
        page_content = await adapter.page.content()
        needs_login = "Sign in to continue" in page_content or "/sign-in" in adapter.page.url
        
        if needs_login:
            logger.info("⚡ Auth state invalid for this domain - performing Clerk login...")
            test_email = os.environ.get("TEST_USER_EMAIL")
            test_password = os.environ.get("TEST_USER_PASSWORD")
            
            if not test_email or not test_password:
                logger.error("TEST_USER_EMAIL and TEST_USER_PASSWORD required for hybrid login")
                logger.error("Set these env vars or generate matching auth state with verify_auth_and_dashboard.py")
                sys.exit(1)
            
            # Perform Clerk login flow
            await adapter.navigate("/sign-in")
            await adapter.page.locator("button", has_text="Sign in to continue").click(timeout=10000)
            await adapter.page.locator("input[name='identifier']").fill(test_email)
            await adapter.page.get_by_role("button", name="Continue", exact=True).click()
            await adapter.page.locator("input[name='password']").fill(test_password)
            await adapter.page.get_by_role("button", name="Continue", exact=True).click()
            await adapter.page.wait_for_url(lambda url: "/sign-in" not in url, timeout=30000)
            
            logger.info("✅ Hybrid login successful")
        else:
            logger.info("✅ Already authenticated")
    except Exception as e:
        logger.warning(f"Auth check/login failed: {e} - continuing anyway (some stories may fail)")


    # Initialize agent
    agent = UISmokeAgent(
        glm_client=glm_client,
        browser=adapter,
        base_url=base_url,
        max_tool_iterations=10,
    )

    # Run stories
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    started_at = datetime.now(timezone.utc).isoformat()
    story_results = []

    for story in stories:
        logger.info(f"\n{'='*60}")
        logger.info(f"Running story: {story.id}")
        logger.info(f"{'='*60}\n")

        try:
            result = await agent.run_story(story)
            story_results.append(result)

            logger.info(f"Story {story.id} completed: {result.status}")
            logger.info(f"  Steps: {len(result.step_results)}")
            logger.info(f"  Errors: {len(result.errors)}")

            # Log errors
            for error in result.errors:
                logger.warning(
                    f"  [{error.severity}] {error.type}: {error.message}"
                )

        except Exception as e:
            logger.exception(f"Unexpected error running story {story.id}")
            from models import AgentError, StepResult, StoryResult

            story_results.append(
                StoryResult(
                    story_id=story.id,
                    status="fail",
                    step_results=[],
                    errors=[
                        AgentError(
                            type="unknown",
                            severity="blocker",
                            message=f"Story execution failed: {e}",
                            details={"exception": str(e)},
                        )
                    ],
                )
            )

    # Clean up
    await adapter.close()
    await browser.close()
    await glm_client.close()

    # Build final report
    completed_at = datetime.now(timezone.utc).isoformat()
    total_errors = {"blocker": 0, "high": 0, "medium": 0, "low": 0}
    for result in story_results:
        for error in result.errors:
            total_errors[error.severity] = total_errors.get(error.severity, 0) + 1

    report = SmokeRunReport(
        run_id=run_id,
        environment=os.environ.get("ENVIRONMENT", "dev"),
        base_url=base_url,
        story_results=story_results,
        total_errors=total_errors,
        started_at=started_at,
        completed_at=completed_at,
        metadata={
            "stories_run": len(stories),
            "stories_passed": sum(1 for r in story_results if r.status == "pass"),
            "stories_failed": sum(1 for r in story_results if r.status == "fail"),
            "total_tokens": glm_client.total_tokens_used,
        },
    )

    # Save report
    output_dir = Path(__file__).parent.parent.parent / "artifacts" / "e2e-agent"
    output_dir.mkdir(parents=True, exist_ok=True)

    report_file = output_dir / f"prime_run_{run_id}.json"

    with open(report_file, "w") as f:
        json.dump(dataclass_to_dict(report), f, indent=2)

    logger.info(f"\n{'='*60}")
    logger.info(f"Smoke test run complete")
    logger.info(f"Report saved to: {report_file}")
    logger.info(f"{'='*60}")
    logger.info(f"Summary:")
    logger.info(f"  Stories run: {len(stories)}")
    logger.info(f"  Passed: {report.metadata['stories_passed']}")
    logger.info(f"  Failed: {report.metadata['stories_failed']}")
    logger.info(f"  Total errors: {sum(total_errors.values())}")
    logger.info(f"    Blockers: {total_errors['blocker']}")
    logger.info(f"    High: {total_errors['high']}")
    logger.info(f"    Medium: {total_errors['medium']}")
    logger.info(f"    Low: {total_errors['low']}")
    logger.info(f"  Tokens used: {report.metadata['total_tokens']}")
    logger.info(f"{'='*60}\n")

    # Exit with non-zero if any blockers or high-priority errors
    if total_errors["blocker"] > 0 or total_errors["high"] > 0:
        logger.error("Critical errors found, exiting with status 1")
        sys.exit(1)

    logger.info("All tests passed or only minor issues found")
    sys.exit(0)


if __name__ == "__main__":
    asyncio.run(main())
