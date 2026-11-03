# kotlinx.serialization：生成的 serializer 靠 @Serializable 注解反射查找，release 打开 minify 时需要以下规则
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class **$$serializer { *; }
-keepclasseswithmembers class * {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class top.dreamsearch.englishcoach.**$$serializer { *; }
-keepclassmembers class top.dreamsearch.englishcoach.** {
    *** Companion;
}
-keepclasseswithmembers class top.dreamsearch.englishcoach.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# 协程
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**
