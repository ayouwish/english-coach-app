package top.dreamsearch.englishcoach.core.di

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider

/**
 * 手写 ViewModel 工厂（不引入 Hilt）。
 *
 * 用法：
 * ```
 * val vm: PracticeViewModel = viewModel(
 *     factory = remember { vmFactory { PracticeViewModel(AppGraph.container) } }
 * )
 * ```
 */
fun <VM : ViewModel> vmFactory(create: () -> VM): ViewModelProvider.Factory =
    object : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T = create() as T
    }
