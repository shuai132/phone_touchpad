plugins { kotlin("jvm") }
java { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach { kotlinOptions.jvmTarget = "17" }
dependencies {
    implementation("org.bouncycastle:bctls-jdk15to18:1.86")
    implementation("org.json:json:20240303")
    testImplementation("junit:junit:4.13.2")
}

sourceSets.test { resources.srcDir("../../Tests/Fixtures") }
tasks.test {
    project.findProperty("interopFile")?.let { systemProperty("touchpad.interop.file", it.toString()) }
    testLogging { events("failed", "skipped") }
}
