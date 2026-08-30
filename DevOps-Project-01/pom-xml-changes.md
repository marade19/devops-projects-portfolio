# pom.xml changes

## Fix: `tomcat-jasper` dependency scope

**Problem:** deploying the WAR to an external Tomcat 9 server failed with a duplicate
servlet-fragment error (`org_apache_jasper_el` found in both `tomcat-embed-el` and
`tomcat-jasper-el`). See BUILD-LOG.md, problem #6, for the full explanation.

**Change:** added `<scope>provided</scope>` to the `tomcat-jasper` dependency.

Before:
```xml
<dependency>
    <groupId>org.apache.tomcat</groupId>
    <artifactId>tomcat-jasper</artifactId>
    <version>9.0.83</version>
</dependency>
```

After:
```xml
<dependency>
    <groupId>org.apache.tomcat</groupId>
    <artifactId>tomcat-jasper</artifactId>
    <version>9.0.83</version>
    <scope>provided</scope>
</dependency>
```

`provided` scope means Maven includes the dependency at compile time (so the code still
builds), but excludes it from the packaged WAR's `WEB-INF/lib/` — it goes into
`WEB-INF/lib-provided/` instead, which Tomcat does not scan for servlet fragments. The
target Tomcat server supplies its own equivalent jar (`tomcat-embed-el`) at runtime, so
nothing is missing — the duplicate is just removed.

## Still open / optional

- **SonarCloud properties** — not yet added. If wiring up Jenkins + SonarCloud later, add
  to the `<properties>` block:
  ```xml
  <sonar.projectKey>your_project_key</sonar.projectKey>
  <sonar.organization>your_organization</sonar.organization>
  <sonar.host.url>https://sonarcloud.io</sonar.host.url>
  ```
  (values come from your SonarCloud project settings — set aside deliberately until the
  Jenkins phase, since it has no bearing on the infrastructure build itself)
