#!/usr/bin/env python3
"""
Generates all pom.xml files:
  - Root pom.xml (parent)
  - Per-proxy pom.xml
  - Per-sharedflow pom.xml
Use --force to overwrite existing files.
"""

import os
import sys
import yaml
import textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FORCE = "--force" in sys.argv


def load_config():
    with open(os.path.join(ROOT, "config", "defaults.yaml")) as f:
        return yaml.safe_load(f)


def write_file(path, content):
    if os.path.exists(path) and not FORCE:
        print(f"  [SKIP] {os.path.relpath(path, ROOT)} (exists, use --force)")
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="\n") as f:
        f.write(content)
    print(f"  [OK]   {os.path.relpath(path, ROOT)}")


def root_pom_xml():
    return textwrap.dedent("""\
        <?xml version="1.0" encoding="UTF-8"?>
        <project xmlns="http://maven.apache.org/POM/4.0.0"
                 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                 xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
                                     http://maven.apache.org/xsd/maven-4.0.0.xsd">
            <modelVersion>4.0.0</modelVersion>

            <groupId>apigee</groupId>
            <artifactId>apigee-proxy-parent</artifactId>
            <version>1.0.0</version>
            <packaging>pom</packaging>
            <name>apigee-proxy-parent</name>

            <properties>
                <apigee.plugin.version>2.5.2</apigee.plugin.version>
                <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
            </properties>

            <profiles>
                <profile>
                    <id>eval</id>
                    <properties>
                        <apigee.org>${org}</apigee.org>
                        <apigee.env>${env}</apigee.env>
                        <apigee.hosturl>https://apigee.googleapis.com</apigee.hosturl>
                        <apigee.apiversion>v1</apigee.apiversion>
                        <apigee.bearer>${bearer}</apigee.bearer>
                        <apigee.options>override</apigee.options>
                        <apigee.proxy.basedir>.</apigee.proxy.basedir>
                        <apigee.delay>5000</apigee.delay>
                        <apigee.config.options>update</apigee.config.options>
                        <apigee.config.dir>${basedir}</apigee.config.dir>
                    </properties>
                </profile>
                <profile>
                    <id>dev</id>
                    <properties>
                        <apigee.org>${org}</apigee.org>
                        <apigee.env>${env}</apigee.env>
                        <apigee.hosturl>https://apigee.googleapis.com</apigee.hosturl>
                        <apigee.apiversion>v1</apigee.apiversion>
                        <apigee.bearer>${bearer}</apigee.bearer>
                        <apigee.options>override</apigee.options>
                        <apigee.proxy.basedir>.</apigee.proxy.basedir>
                        <apigee.delay>5000</apigee.delay>
                        <apigee.config.options>update</apigee.config.options>
                        <apigee.config.dir>${basedir}</apigee.config.dir>
                    </properties>
                </profile>
                <profile>
                    <id>prod</id>
                    <properties>
                        <apigee.org>${org}</apigee.org>
                        <apigee.env>${env}</apigee.env>
                        <apigee.hosturl>https://apigee.googleapis.com</apigee.hosturl>
                        <apigee.apiversion>v1</apigee.apiversion>
                        <apigee.bearer>${bearer}</apigee.bearer>
                        <apigee.options>override</apigee.options>
                        <apigee.proxy.basedir>.</apigee.proxy.basedir>
                        <apigee.delay>5000</apigee.delay>
                        <apigee.config.options>update</apigee.config.options>
                        <apigee.config.dir>${basedir}</apigee.config.dir>
                    </properties>
                </profile>
            </profiles>

            <build>
                <plugins>
                    <plugin>
                        <groupId>org.apache.maven.plugins</groupId>
                        <artifactId>maven-resources-plugin</artifactId>
                        <version>3.3.1</version>
                        <executions>
                            <execution>
                                <id>copy-apiproxy-to-target</id>
                                <phase>process-resources</phase>
                                <goals>
                                    <goal>copy-resources</goal>
                                </goals>
                                <configuration>
                                    <outputDirectory>${project.build.directory}/apiproxy</outputDirectory>
                                    <overwrite>true</overwrite>
                                    <resources>
                                        <resource>
                                            <directory>${basedir}/apiproxy</directory>
                                            <filtering>false</filtering>
                                        </resource>
                                    </resources>
                                </configuration>
                            </execution>
                        </executions>
                    </plugin>
                    <plugin>
                        <groupId>io.apigee.build-tools.enterprise4g</groupId>
                        <artifactId>apigee-edge-maven-plugin</artifactId>
                        <version>${apigee.plugin.version}</version>
                        <executions>
                            <execution>
                                <id>deploy-proxy</id>
                                <phase>install</phase>
                                <goals>
                                    <goal>configure</goal>
                                    <goal>deploy</goal>
                                </goals>
                            </execution>
                        </executions>
                    </plugin>
                    <plugin>
                        <groupId>com.apigee.edge.config</groupId>
                        <artifactId>apigee-config-maven-plugin</artifactId>
                        <version>2.7.1</version>
                        <executions>
                            <execution>
                                <id>create-config-apiproduct</id>
                                <phase>install</phase>
                                <goals><goal>apiproducts</goal></goals>
                            </execution>
                            <execution>
                                <id>create-config-developer</id>
                                <phase>install</phase>
                                <goals><goal>developers</goal></goals>
                            </execution>
                            <execution>
                                <id>create-config-developerapps</id>
                                <phase>install</phase>
                                <goals><goal>apps</goal></goals>
                            </execution>
                        </executions>
                    </plugin>
                </plugins>
            </build>

            <pluginRepositories>
                <pluginRepository>
                    <id>central</id>
                    <name>Maven Central</name>
                    <url>https://repo1.maven.org/maven2</url>
                    <releases><enabled>true</enabled></releases>
                    <snapshots><enabled>false</enabled></snapshots>
                </pluginRepository>
                <pluginRepository>
                    <id>apigee-config-releases</id>
                    <name>Apigee Config Maven Repo</name>
                    <url>https://apigee.github.io/apigee-config-maven-plugin/maven/repo</url>
                </pluginRepository>
                <pluginRepository>
                    <id>apigee-edge-releases</id>
                    <name>Apigee Edge Maven Repo</name>
                    <url>https://apigee.github.io/apigee-edge-maven-plugin/maven/repo</url>
                </pluginRepository>
            </pluginRepositories>
        </project>
    """)


def child_pom_xml(artifact_id, relative_path="../../pom.xml"):
    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8"?>
        <project xmlns="http://maven.apache.org/POM/4.0.0">
            <modelVersion>4.0.0</modelVersion>
            <parent>
                <groupId>apigee</groupId>
                <artifactId>apigee-proxy-parent</artifactId>
                <version>1.0.0</version>
                <relativePath>{relative_path}</relativePath>
            </parent>
            <artifactId>{artifact_id}</artifactId>
            <packaging>pom</packaging>
            <name>{artifact_id}</name>
        </project>
    """)


def main():
    cfg = load_config()
    print("\n==> Generating pom.xml files")

    # Root pom
    write_file(os.path.join(ROOT, "pom.xml"), root_pom_xml())

    # Per-proxy pom
    for proxy in cfg.get("api_proxies", []):
        name = proxy["name"]
        write_file(
            os.path.join(ROOT, "apiproxies", name, "pom.xml"),
            child_pom_xml(name),
        )

    # Per-sharedflow pom
    for flow in cfg.get("shared_flows", []):
        name = flow["name"]
        write_file(
            os.path.join(ROOT, "sharedflows", name, "pom.xml"),
            child_pom_xml(name),
        )

    total = 1 + len(cfg.get("api_proxies", [])) + len(cfg.get("shared_flows", []))
    print(f"\n==> Done. {total} pom.xml files generated.\n")


if __name__ == "__main__":
    main()
