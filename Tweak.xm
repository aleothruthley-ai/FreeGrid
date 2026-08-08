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
    // 核心防御：绝对不能让底部的 Dock 栏允许空隙，否则 Dock 排版会乱掉
    if ([self respondsToSelector:@selector(iconLocation)]) {
        NSString *location = [self iconLocation];
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

// 屏蔽系统原生的向左上角压缩靠拢的算法
- (void)compactIcons {
    // 留空，什么都不做
}

// 欺骗系统：告诉它当前的网格布局永远是“完美”的
- (BOOL)isGridLayoutValid {
    return YES;
}

- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options {
    return YES;
}

- (BOOL)isGridLayoutValid:(id)arg1 {
    return YES;
}

- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options outOfBoundsIcons:(id *)icons {
    if (icons) *icons = @[];
    return YES;
}


// ===================================================================
// 3. 【核心修复】：拦截挤压修复方法，解决移除图标时的崩溃！
// ===================================================================
// 之前的崩溃是因为返回了 nil，被底层 NSMutableSet addObjectsFromArray 拒收。
// 现在强制返回空数组 @[]，告诉系统 0 个图标发生了推挤，完美化解异常！

- (id)_updateModelByRepairingGapsIfNecessary {
    return @[];
}

- (id)_updateModelByRepairingGapsIfNecessaryAvoidingIcons:(id)icons {
    return @[];
}

- (id)repairModelByEliminatingGapsInIcons:(id)icons avoidingIcons:(id)avoidingIcons {
    return @[]; 
}


// ===================================================================
// 4. 用户交互拦截：当用户拖拽放下图标时，强行将其坐标锁死！
// ===================================================================

// 当插入一个图标到网格中时
- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutOptions {
    id result = %orig;
    if (icon && [self respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
        [self setFixedLocation:index forIcon:icon];
    }
    return result;
}

// 当移动一个已存在的图标到新的网格坑位时
- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutOptions {
    id result = %orig;
    if (icon && [self respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
        [self setFixedLocation:index forIcon:icon];
    }
    return result;
}

%end
