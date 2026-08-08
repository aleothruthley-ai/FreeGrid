#import <UIKit/UIKit.h>

// 声明 iOS 底层私有方法，防止编译报错
@interface SBIconListView : UIView
- (NSString *)iconLocation;
@end

@interface SBIconListModel : NSObject
- (void)setFixedLocation:(unsigned long long)location forIcon:(id)icon;
@end

// ===================================================================
// 1. 视图层：开放桌面网格存在空隙 (Gaps) 的权限
// ===================================================================
%hook SBIconListView

- (BOOL)allowsGaps {
    if ([self respondsToSelector:@selector(iconLocation)]) {
        NSString *location = [self iconLocation];
        // 核心防御：绝对不能让底部的 Dock 栏允许空隙，否则 Dock 会排版错乱
        if (location && [location containsString:@"Dock"]) {
            return %orig;
        }
    }
    return YES; // 让普通的桌面视图全面支持留空
}

%end


// ===================================================================
// 2. 数据层：接管并锁死系统原生的位置记录，彻底解决崩溃！
// ===================================================================
%hook SBIconListModel

// 允许数据模型开启"固定图标位置"功能
- (BOOL)allowsFixedIconLocations {
    return YES;
}

// 强制开启系统底层的固定位置行为 (1 = Enabled)
- (long long)fixedIconLocationBehavior {
    return 1;
}

// 【安全防线 1】：从源头瘫痪系统的网格挤压靠拢算法
// 只要这个方法不执行，系统就不会把你的图标往左上角推挤。
// 绝不去 Hook 那些带返回值的 repair 修复方法，彻底杜绝 NSMutableSet 崩溃！
- (void)compactIcons {
    // 留空，什么都不做，拒绝压缩靠拢
}

// 【安全防线 2】：当从其它地方（比如 App 资源库）拖入新图标时
- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutOptions {
    id result = %orig;
    // 原生插入成功后，立刻调用苹果的打桩方法，把坐标锁死在 IconState.plist 里
    if (icon && [self respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
        [self setFixedLocation:index forIcon:icon];
    }
    return result;
}

// 【安全防线 3】：当在桌面内移动图标时
- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutOptions {
    id result = %orig;
    // 移动成功后，同样立刻打桩，解决低概率移动不生效、回弹的问题！
    if (icon && [self respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
        [self setFixedLocation:index forIcon:icon];
    }
    return result;
}

%end
