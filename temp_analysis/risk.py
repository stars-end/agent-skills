#!/usr/bin/env python3
"""
Risk Assessment Module

Provides reusable risk assessment logic based on change analysis.
Used by /merge, /sync-coordination, /guardrails.
"""

import json
from typing import Dict, List
import subprocess
from .analysis import analyze_current_changes


def _default_branch() -> str:
    try:
        res = subprocess.run(['git', 'remote', 'show', 'origin'], capture_output=True, text=True)
        for line in res.stdout.splitlines():
            if 'HEAD branch:' in line:
                return line.split(':', 1)[1].strip()
    except Exception:
        pass
    return 'master'


class RiskAssessor:
    """Assess risk level of changes"""

    # Risk thresholds
    HIGH_RISK_LOC = 500
    MEDIUM_RISK_LOC = 100

    # Risk weights by category (higher = more risky)
    CATEGORY_WEIGHTS = {
        'schema': 10,      # Highest risk - database changes
        'auth': 10,        # Highest risk - security critical
        'api': 5,          # High risk - breaking changes possible
        'config': 5,       # High risk - can break deployments
        'frontend': 2,     # Medium risk - UI changes
        'tests': 1,        # Low risk - tests only
        'docs': 1,         # Low risk - documentation
    }

    def assess_risk(self, analysis: Dict = None, target_branch: str = None) -> Dict:
        """
        Assess risk level of current changes.

        Args:
            analysis: Pre-computed analysis dict (optional)
            target_branch: Branch to compare against

        Returns:
            Dictionary with risk level, factors, and recommendations
        """
        if analysis is None:
            from .analysis import analyze_current_changes
            branch = target_branch or _default_branch()
            analysis = analyze_current_changes(branch, committed=True)

        risk_level = self._calculate_risk_level(analysis)
        factors = self._identify_risk_factors(analysis)
        recommendations = self._generate_recommendations(risk_level, factors)

        return {
            'level': risk_level,           # HIGH, MEDIUM, LOW
            'score': self._calculate_risk_score(analysis),
            'factors': factors,
            'recommendations': recommendations,
            'analysis': analysis
        }

    def _calculate_risk_level(self, analysis: Dict) -> str:
        """Calculate overall risk level"""
        categories = analysis['files']['by_category']
        net_lines = analysis['stats']['net']

        # HIGH RISK indicators
        if categories.get('schema') or categories.get('auth'):
            return 'HIGH'
        if net_lines > self.HIGH_RISK_LOC:
            return 'HIGH'

        # MEDIUM RISK indicators
        if categories.get('api') or categories.get('config'):
            return 'MEDIUM'
        if net_lines > self.MEDIUM_RISK_LOC:
            return 'MEDIUM'

        # LOW RISK
        return 'LOW'

    def _calculate_risk_score(self, analysis: Dict) -> int:
        """Calculate numeric risk score (0-100)"""
        score = 0
        categories = analysis['files']['by_category']

        # Add weighted score for each category
        for category, files in categories.items():
            if files:
                weight = self.CATEGORY_WEIGHTS.get(category, 1)
                score += len(files) * weight

        # Add LOC contribution
        net_lines = analysis['stats']['net']
        if net_lines > self.HIGH_RISK_LOC:
            score += 30
        elif net_lines > self.MEDIUM_RISK_LOC:
            score += 15

        return min(score, 100)  # Cap at 100

    def _identify_risk_factors(self, analysis: Dict) -> List[Dict]:
        """Identify specific risk factors"""
        factors = []
        categories = analysis['files']['by_category']
        net_lines = analysis['stats']['net']

        # Schema changes
        if categories.get('schema'):
            factors.append({
                'category': 'schema',
                'severity': 'HIGH',
                'description': f"Database schema changes ({len(categories['schema'])} files)",
                'impact': 'Can cause migration conflicts and data integrity issues'
            })

        # Auth changes
        if categories.get('auth'):
            factors.append({
                'category': 'auth',
                'severity': 'HIGH',
                'description': f"Authentication changes ({len(categories['auth'])} files)",
                'impact': 'Security-critical changes require careful review'
            })

        # API changes
        if categories.get('api'):
            factors.append({
                'category': 'api',
                'severity': 'MEDIUM',
                'description': f"API endpoint changes ({len(categories['api'])} files)",
                'impact': 'May introduce breaking changes for clients'
            })

        # Large changeset
        if net_lines > self.HIGH_RISK_LOC:
            factors.append({
                'category': 'volume',
                'severity': 'HIGH',
                'description': f"Very large changeset ({net_lines} lines)",
                'impact': 'Difficult to review, higher chance of bugs'
            })
        elif net_lines > self.MEDIUM_RISK_LOC:
            factors.append({
                'category': 'volume',
                'severity': 'MEDIUM',
                'description': f"Large changeset ({net_lines} lines)",
                'impact': 'Consider breaking into smaller changes'
            })

        # Config changes
        if categories.get('config'):
            factors.append({
                'category': 'config',
                'severity': 'MEDIUM',
                'description': f"Configuration changes ({len(categories['config'])} files)",
                'impact': 'Can affect deployments and environment behavior'
            })

        return factors

    def _generate_recommendations(self, risk_level: str, factors: List[Dict]) -> List[str]:
        """Generate actionable recommendations based on risk"""
        recommendations = []

        if risk_level == 'HIGH':
            recommendations.append("⚠️  HIGH RISK: Require thorough review before merging")
            recommendations.append("Consider breaking changes into smaller, focused PRs")

        # Category-specific recommendations
        has_schema = any(f['category'] == 'schema' for f in factors)
        has_auth = any(f['category'] == 'auth' for f in factors)
        has_api = any(f['category'] == 'api' for f in factors)

        if has_schema:
            recommendations.append("Run /db-verify to ensure schema consistency")
            recommendations.append("Verify migrations are reversible")

        if has_auth:
            recommendations.append("Security review required for auth changes")
            recommendations.append("Test authentication flows thoroughly")

        if has_api:
            recommendations.append("Update API documentation")
            recommendations.append("Consider API versioning for breaking changes")

        if risk_level in ['HIGH', 'MEDIUM']:
            recommendations.append("Run full test suite (/sync-coordination --ci)")

        return recommendations


def assess_current_risk(target_branch: str = None) -> Dict:
    """
    Convenience function to assess current risk.

    Usage:
        from lib.risk import assess_current_risk
        risk = assess_current_risk()
        if risk['level'] == 'HIGH':
            print("High risk changes detected!")
    """
    assessor = RiskAssessor()
    return assessor.assess_risk(target_branch=target_branch or _default_branch())


def format_risk_output(risk: Dict) -> str:
    """Format risk assessment for display"""
    output = []
    output.append(f"⚠️  Risk Level: {risk['level']}")
    output.append(f"Risk Score: {risk['score']}/100\n")

    if risk['factors']:
        output.append("Risk Factors:")
        for factor in risk['factors']:
            output.append(f"├─ [{factor['severity']}] {factor['description']}")
            output.append(f"│  └─ Impact: {factor['impact']}")

    if risk['recommendations']:
        output.append("\n💡 Recommendations:")
        for rec in risk['recommendations']:
            output.append(f"  {rec}")

    return '\n'.join(output)


if __name__ == '__main__':
    # CLI usage
    import sys

    target = sys.argv[1] if len(sys.argv) > 1 else _default_branch()
    risk = assess_current_risk(target)

    if '--json' in sys.argv:
        print(json.dumps(risk, indent=2))
    else:
        print(format_risk_output(risk))
