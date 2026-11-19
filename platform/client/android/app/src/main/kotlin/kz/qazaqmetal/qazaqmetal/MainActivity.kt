package kz.qazaqmetal.qazaqmetal

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannels(listOf(
                NotificationChannel("favorite_offers", "Избранные заведения", NotificationManager.IMPORTANCE_DEFAULT),
                NotificationChannel("union_updates", "Новые заведения", NotificationManager.IMPORTANCE_DEFAULT),
                NotificationChannel("partner_updates", "События партнёра", NotificationManager.IMPORTANCE_DEFAULT)
            ))
        }
    }
}
