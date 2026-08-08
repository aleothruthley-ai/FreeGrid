#import <UIKit/UIKit.h>

// ===================================================================
// FreeGrid - iOS 17+ 桌面图标任意摆放
// 
// 核心思路：全面开启 Apple 原生的 allowsGaps 与 fixedLocation 属性，
// 并拦截底层 Model 让系统误以为所有图标都是"钉"死在桌面的。
// 不进行任何手动坐标干预，100% 原生级流畅、零卡顿、零残影。
// ===================================================================


// ==========================================
// 1. 视图层 (View Layer)
// ==========================================
%hook SBIconListView

// 强制视图层允许出现间隙 (Gaps)
// 这样在拖拽图标放下时，系统会精准返回手指所在的 GridCellIndex (网格坑位)，而不再是强制吸附到最后一个空位
- (BOOL)allowsGaps {
    return YES;
}

// 防御性 Hook：忽略系统在某些特殊排版时强制关闭 Gaps 的行为
- (void)setAllowsGaps:(BOOL)gaps {
    %orig(YES);
}

%end


// ==========================================
// 2. 数据模型层 (Model Layer)
// ==========================================
%hook SBIconListModel

// 允许当前列表固定图标位置
- (BOOL)allowsFixedIconLocations {
    return YES;
}

// 强制所有列表声明其包含了固定位置的图标
- (BOOL)hasFixedIconLocations {
    return YES;
}

// 强制设置图标固定位置行为模式为 1 (通常代表 Enabled)
- (long long)fixedIconLocationBehavior {
    return 1;
}

- (void)setFixedIconLocationBehavior:(long long)behavior {
    %orig(1);
}

// 【终极杀招：禁止系统推挤图标】
// Apple 的 repairModelByEliminatingGapsInIcons 算法会遍历图标并试图填补空隙。
// 但是只要一个图标被标记为 Fixed (固定)，算法就会主动跳过它。
// 我们强制让所有图标返回 YES，彻底瘫痪系统的推挤收缩机制，完美保留空隙！

- (BOOL)isIconFixed:(id)icon {
    return YES;
}

- (BOOL)isIconFixed:(id)icon gridCellInfoOptions:(unsigned long long)options {
    return YES;
}

- (BOOL)isIcon:(id)icon fixedAtGridCellIndex:(unsigned long long)index {
    return YES;
}

- (BOOL)isIcon:(id)icon fixedAtGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options {
    return YES;
}

// 作为双重保险，拦截并架空 iOS 17.0/17.2 头文件中的空隙修补触发方法
- (id)_updateModelByRepairingGapsIfNecessary {
    return self;
}

- (id)_updateModelByRepairingGapsIfNecessaryAvoidingIcons:(id)icons {
    return self;
}

- (id)repairModelByEliminatingGapsInIcons:(id)icons avoidingIcons:(id)avoidingIcons {
    return icons; // 原样返回，坚决不清除空隙
}

%end
